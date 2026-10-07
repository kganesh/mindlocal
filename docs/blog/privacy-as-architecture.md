# What it takes to ask your journal a question

*Part four, and the first one with an app attached.*

---

The last three posts here were about a memory graph: [how it is
built](https://medium.com/@ganesh.kolekar/from-people-graph-to-memory-graph-designing-for-selective-recall-788ed4ed2e6b),
[how a question finds its evidence in it](<PART 2 URL>), and [what an answer
can be checked against](<PART 3 URL>). That work is now an app called
InnerSage, [in beta on TestFlight](https://testflight.apple.com/join/jjU4K1sy).

Storing what you write is easy. The hard part is answering a question about it
without inventing anything, on a phone, from a model small enough to live
there.

## The journal becomes a graph

Every entry is read for the people, activities, outcomes and decisions inside
it. Those become typed nodes with edges between them, sitting alongside your
text rather than replacing it. Your writing is never rewritten.

A question walks that graph rather than searching your entries. The person
named in the question is resolved once, in the People list, where the app has
nicknames and aliases and can ask you which Sam you meant. From there the
address is the person's database ID, so two people called Sam are two different
addresses and there is no way to land on the wrong one. Evidence is then scored
outward from them: a reminder you still owe someone beats a note you wrote,
which beats knowing they are family.

## Some questions never reach a model

"When did I last see Sarah" is a maximum over dated evidence. It is computed in
Swift and no model is asked, because the only way to be certain about a date is
to work it out.

That rule came from a question the app got wrong. Asked whether Nora's birthday
happened last week, it answered that Nora's birthday is on 2 August. The date
was real. It belonged to Rohan. Nora does not exist anywhere in the journal.
Retrieval had done its job, the evidence was correct, the time window was
correct, and the model still attached a true fact to a name it had never seen.

A fluent, specific, wrong answer is the failure worth designing against,
because you cannot spot it without going and checking the source yourself. So
three things sit between a question and an answer. Names the app has never seen
are refused instead of answered. Questions about someone written about but
never added to People are told apart from questions about nobody at all. And
the answer that comes back is checked against the evidence that was actually
supplied before you see it.

## Where the answering happens

Dictation, sentence embeddings, building the graph and searching it all run on
the phone. Your entries live in the app's own database there, and in your own
device backup under your Apple Account.

Generation is the one part that reaches for more room than a phone has. It goes
to Apple's Private Cloud Compute where the device supports it, and to the
on-device model otherwise. The reason is context: roughly 32K tokens against
the on-device model's 4K, which decides whether a question can be answered from
a handful of entries or from a year of them. Entry and question text does leave
the phone on that path. Private Cloud Compute is built so that Apple cannot
read it and keeps nothing once the request ends, and I never see it either.

Routing is decided per request rather than by a setting. The app requires Apple
Intelligence and does not run without it.

What falls out of building it this way: there is no account, no sign-up and no
server of mine, so there is no database of entries for me to secure or to lose.
There is no analytics, no crash reporting and no advertising. Health data,
your calendar and your recorded voice never leave the device at all.

## The lock assumes your phone is sometimes in someone else's hands

Face ID is off by default. Turning it on is a statement that other people
handle this phone, and the rest follows from taking that literally.

The device passcode always works as a second route, because authentication asks
for device-owner authentication rather than the biometrics-only policy. A
journal behind a face that a cut lip can defeat, with no way back in, is a way
to lose years of writing.

The cover goes on when the app becomes inactive rather than when it backgrounds,
because iOS photographs the screen for the app switcher on the way out and that
snapshot is as readable as the journal. It is opaque rather than blurred, since
a blurred page still shows its shape and the colour of a mood. Only a real trip
to the background asks for your face again, so opening Control Centre does not
lock you out of your own sentence.

## Try it

The beta is open, and what helps most is someone writing in it across a couple
of weeks rather than one sitting.

The report I want above all others is an answer that got something factually
wrong about your own entries. Each answer cites the entries behind it, so the
question and what it said is usually enough for me to find the fault. After
that, anywhere the app did something you did not expect.

An iPhone 15 Pro or later on iOS 26, with Apple Intelligence turned on. Free,
nothing to buy, no mailing list.

TestFlight: https://testflight.apple.com/join/jjU4K1sy
