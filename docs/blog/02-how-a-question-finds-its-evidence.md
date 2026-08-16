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

Four steps. Find Lilly. Score what is connected to her. Keep the question's other filters on topic. Write out what survives.

### Step 1: Don't search the graph for the person

The obvious approach is to look through every node for one named "Lilly". We don't do that.

People are already stored in the app's database, with their names and nicknames. We look the name up there — that step handles nicknames, and can ask you which Sam you meant. Once it hands back a person, we *build* the graph address out of it.

The address is nothing clever. It is the word "person" followed by that person's database ID. Entries and reminders work the same way, each tagged with what it is.

*[Figure 1: a name is resolved once in the People list; the person's database ID then becomes their address in the graph.]*

Two things follow from that.

**It is exact.** The address comes from the database ID, not the name. Two people called Sam get two different addresses, so there is no way to land on the wrong one. The matching that can go wrong happens once, in the People list, where the app has nicknames and can ask you. Inside the graph there is no guessing left to do.

**There is nothing to keep in sync.** The alternative is to hand each node a random ID and keep a table mapping people to nodes — one more thing to store, one more thing to go stale. Here there is no table. Given the person, the address can be worked out at any time.

### Step 2: Score the person, then score everything attached to her

Lilly's node gets a score of 100. Then we walk every link connected to her, and each node on the other end gets a score of its own, decided by the type of link.

Nothing is divided up. The 100 is not a pool to share out — it is a strong opening anchor for the person the question is about. Connected evidence can still finish above her once other signals stack up.

*[Figure 2: one step out from the person named in the question.]*

Different link types are worth different amounts:

| link type | score it passes on |
|---|---|
| has reminder / is about person | 28 |
| has conflict / was with person | 24 |
| has event | 22 |
| has entry / mentions | 20 |
| has decision | 18 |
| is related to (family) | 14 |

These are not learned weights. They encode a retrieval policy we chose.

A reminder you have not done yet beats a note you wrote, because something you still owe someone is more useful than something you already wrote about. Family relationships score lowest of all: knowing Lilly is your wife helps you make sense of the other results, but it is not itself an answer to "what should I ask her". It is background, not evidence.

Any ranking system ends up expressing an opinion in its numbers. It is better to know what yours is saying.

### Step 3: Keep the question's filters on topic

Questions carry more than a name. "Tonight" means a time. "Meeting" means events. Those are worth scoring too — but only against nodes actually connected to the person in the question.

A filter does not know who a node belongs to. A date is just a date; left loose, it will happily rank a stranger's meeting above your wife's. So filters run on a leash: they apply to the person's own connected nodes, and the leash comes off only when the question names nobody, because then there is no subject to stay near.

*[Figure 3: the same "meeting" filter, with and without the leash.]*

Time goes one step further. A period named in the question is a **constraint, not a preference** — evidence from outside it is removed, not merely ranked lower. Scoring a window and then letting an older entry through on some other signal is how "what did I do last week" ends up answered with something from a month ago.

### Step 4: Take the best, look one step further, then stop

The highest-scoring nodes become the starting set. Each passes score along its own links at half strength, which picks up the entry *behind* a reminder or the argument *inside* a conflict. Then it stops: about ten nodes go to the model.

The limit is not about speed. Models that run on your phone can only read so much at once, and every line of old text takes up room the actual question needs. Because there is a ceiling, order decides what gets cut — so evidence is written out in score order, most useful first, and anything trimmed is whatever mattered least.

## What the model actually receives

Retrieval picks the nodes. How they are written down turns out to matter just as much.

The compact, machine-shaped version looks like this:

```
[event, 2026-08-02] Akhil's birthday (domain: other, location: 4545 Celia Ct)
Akhil's birthday --happenedAt--> 4545 Celia Ct (4545 Celia Ct)
```

We write full sentences instead:

```
On Sunday 2 August 2026 (13 days ago), there was an event called "Akhil's
birthday". It involved Akhil. It took place at 4545 Celia Ct, Fremont, CA.
```

Three things change with that.

**The arrows disappear.** They only existed because the first line could not say where something happened or who was there. Fold those facts into the sentence and there is nothing left to draw.

**Dates stop needing arithmetic.** "Sunday 2 August 2026 (13 days ago)" states directly what a small model is worst at working out — whether a date falls inside the period the question asked about.

**There are fewer loose pieces to recombine.** Fragments invite a model to join things that were never joined. A finished sentence says what belongs together, and just as usefully, what doesn't.

These sentences are assembled in code, not written by a model. That is deliberate. A generated context would put an invention *upstream* of the question, where nothing downstream could catch it — the context is the one part of the pipeline that has to be incapable of making things up.

## What this gets us

The whole path is a few hundred lines. The scoring, the graph walking and the writing-out are all deterministic — no embeddings, no similarity search, no model call. Those happen elsewhere in the pipeline. This part is plain arithmetic on a graph: work out an address, score everything attached to it, keep the filters on topic, stop at ten.

What it gets us is that **every retrieved item can be explained**. This node is here because it is connected to this person, by this kind of link, within this time range. When an answer looks wrong, you can find out exactly what the model was given, instead of shrugging at a similarity score you cannot inspect.

Whether the *answer* holds up is a separate question, and not one retrieval can settle. That is the next post.

---

*Next: how we use the same graph to check the model's answers — and why "checkable" is not the same as "true".*
