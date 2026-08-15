# Scoring Memory: How a Question Finds Its Evidence

*Part 2 of 4 on the memory graph behind MindLocal. [Part 1](https://medium.com/@ganesh.kolekar/from-people-graph-to-memory-graph-designing-for-selective-recall-788ed4ed2e6b) covered how the graph is built. This post covers what happens when you ask it a question.*

---

An app that keeps everything you write is not useful on its own. The hard part is not storing the text. It is picking the right ten things out of a thousand and showing the model only those.

Part 1 ended with a graph. Two words to get out of the way, since the rest of this post leans on them:

- A **node** is one thing. A person. A note you wrote. A reminder. A meeting.
- An **edge** is a link between two things, and it has a type. *Lilly* → *has reminder* → *ask about the school form*.

That structure on its own does not answer anything. Something still has to decide which nodes matter for the question you just asked.

## The question

> "What should I ask Lilly before dinner tonight?"

Three things have to happen. Find Lilly. Find what is connected to her. Decide how much of it is worth showing the model.

### Step 1: Don't search the graph for the person

The obvious approach is to look through every node for one named "Lilly". We don't do that.

People are already stored in the app's database, with their names and nicknames. We look the name up there — that step handles nicknames, and can ask you which Sam you meant. Once it hands back a person, we *build* the graph address out of it.

The address is nothing clever. It is the word "person" followed by that person's database ID. Entries and reminders work the same way, each tagged with what it is.

*[Figure 1: a name is resolved once in the People list; the person's database ID then becomes their address in the graph.]*

**Once the lookup has picked a person, the graph address is exact.** Two people called Sam have different database IDs, so they get different node IDs — they cannot collide at the graph layer. The matching that can go wrong happens once, in the People list, where the app has nicknames and a way to ask you. Inside the graph there is no guessing left to do.

**And there is nothing to keep in sync.** The other option is to give each node a random ID when you build the graph, then keep a table mapping each person to their node. That table is one more thing to store, and one more thing that can go out of date. Here there is no table.

### Step 2: Score the person, then score everything attached to her

Lilly's node gets a score of 100. Then we walk every link connected to her, and each node on the other end gets a score of its own, decided by the type of link.

Nothing is being divided up here. The 100 is not a pool to share out — it is a strong opening anchor for the person the question is about. Connected evidence can still finish above her once the other signals below stack up. If she has ten reminders, all ten score the same as if she had one.

Her dinner tonight, her open reminders, an argument that was never settled, entries that mention her — all of them get a score, because all of them are one link away.

The part worth pausing on is that different edge types are worth different amounts:

| edge type | score it passes on |
|---|---|
| has reminder / is about person | 28 |
| has conflict / was with person | 24 |
| has event | 22 |
| has entry / mentions | 20 |
| has decision | 18 |
| is related to (family) | 14 |

Scores add up, so a node reached by more than one link collects more than one score. In practice each record is linked to a person from both ends — the reminder points at her, and she points back at it — so every record picks up its score twice.

That kept the order among records the same, which is why it took us a while to notice. But it also doubled how much a link counts against the signals that are only applied once, further down: matching the question's topic, its time range, its wording. Connection to a person ended up weighing twice what the table suggests.

These are not learned weights. They encode a retrieval policy we chose.

A reminder you have not done yet beats a note you wrote, because something you still owe someone is more useful than something you already wrote about. And family relationships score lowest of all. Knowing Lilly is your wife helps you make sense of the other results, but it is not itself an answer to "what should I ask her". It is background, not evidence.

Any ranking system ends up expressing an opinion in its numbers. It is better to know what yours is saying.

### Step 3: Filters have to stay on topic

Questions carry more than a name. "Tonight" means a time. "Meeting" means events. So we also add score to nodes that match those.

Our first version added that score to the whole graph. Ask about Lilly and a meeting, and *every meeting you have ever had* got the bonus — including a dentist appointment from March that had nothing to do with her.

The fix is a leash. Before any of those filters run, we work out which nodes are actually connected to the person in the question, and let the filters touch only those. If the question names nobody at all, the leash comes off and the filters apply everywhere — which is right, because then there is no subject to stay near.

*[Figure 2: the same "meeting" filter, with and without the leash.]*

The general lesson: **a filter does not know who a node belongs to.** A date is just a date. It will happily rank a stranger's meeting above your wife's. Either tie the filter to the subject of the question, or don't use it.

### Step 4: Take the best, look one step further, then stop

The highest-scoring nodes become our starting set. Each one passes score along its own edges too, at half strength. That picks up the entry *behind* a reminder, or the argument *inside* a conflict.

Then we stop. About ten nodes go to the model.

The limit is not about speed. Models that run on your phone can only read so much at once, and every line of old text takes up room the actual question needs.

## Four things we got wrong

Most of the decisions above only make sense once you know what went wrong first.

### Sorting things neatly broke the ranking

We used to arrange the results before sending them: meetings first, newest first. It looked tidy.

The problem is that the step after ours cuts text off the **end** when there is too much. So the single most useful result, sitting politely in the middle of a tidy list, was one of the first things thrown away.

Now results go out in score order. The most useful thing is first, and whatever gets cut is whatever mattered least.

> If something later cuts your list short, then the order of that list is a priority order, whether you meant it that way or not.

### Something we never handled just quietly did nothing

"Tonight" and "next week" matched nothing at all. The code only understood *today*, *yesterday*, *this week*, and *recently* — all of which look backwards.

It got worse. We measured how relevant a date was by how far it sat from right now, ignoring whether it was in the past or the future. So a reminder due today and one due next week scored exactly the same, and the tie was broken by an internal ID string. In other words, at random.

Nothing crashed. Nothing showed up in the logs. The results were just slightly wrong, and looked like a judgement call.

> Something you never handled does not fail loudly. It looks like a quirk.

### A safe path with an unsafe fallback

Ask "who is Tommy?" about a name you have never saved, and the app answered: *"Tommy is your brother."*

We already had code for this. Questions about who someone is go down a separate path that just says "I don't have anyone by that name" — no model involved, so nothing can be made up. It never ran.

Deciding which path to take was itself a model call. When that call failed, the fallback was "treat it as a normal question" — the path that hands the model everything it knows and lets it fill in the gap.

That fallback was written when the model call only chose a sort order. Falling back to "no sorting" was genuinely harmless. It stopped being harmless when something safety-related started depending on it.

> When a fallback decides which safety path you take, "just do the usual thing" is not a neutral choice.

### "Not in your list" was hiding two different answers

If someone is not in your People list, there are two possibilities. You have never mentioned them. Or you have written about them ten times and never got round to adding them.

Answering "I don't know that name" to both throws away something the graph already knows, because names we could not match are still stored as nodes.

Now the second case gets a real answer: *"Tommy isn't in your People list, but your notes mention them 5 times. Most recent: …"* That sentence is built from the titles and dates we already have. No model is involved, so it cannot invent a relationship it has no record of.

## What this gets us

The whole thing is a few hundred lines. The scoring, the graph walking and the packing at this stage are all deterministic — no embeddings, no similarity search, no model call. Those happen elsewhere in the pipeline. This part is plain arithmetic on a graph: work out an address, score everything attached to it, keep the filters on topic, stop at ten.

What it gets us is that **every retrieved item can be explained**. This node is here because it is connected to this person, by this kind of link, within this time range. When an answer looks wrong, you can at least find out what the model was given, instead of shrugging at a similarity score you cannot inspect.

Whether the *answer* holds up is a separate question, and not one retrieval can settle. That is the next post.

Choosing well is not about a smarter model. It is about knowing what to leave out, and being able to say why.

---

*Next: how we use the same graph to check the model's answers — and why "checkable" is not the same as "true".*
