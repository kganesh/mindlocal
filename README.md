# MindLocal

A private journal for your own life, on your own phone. Write or speak about your
day, and a model turns it into something you can ask questions of later: who was
there, what you decided, how it turned out, what you keep repeating.

The app ships as **The Little Things**. MindLocal is the project, the bundle id
and this repository.

There are no accounts and no servers of ours. The journal is stored only on your
phone, and transcription and speech synthesis run entirely on the device.

> This started as "DecisionMemory", a scaffold for capturing decisions. It grew
> into a daily journal that still tracks decisions as one kind of entry among
> several. Some older documents still use the original name.

## Where the model runs

Generation goes to Apple's Private Cloud Compute when the device and OS support
it, and to the on-device model otherwise. PCC is enabled, the managed
entitlement is granted, and the reason for using it is context: roughly 32K
tokens against the on-device model's 4K, which is the difference between
answering from a handful of entries and answering from a year of them.

This means entry and question text leaves the phone on that path. PCC is built
so that Apple cannot read it and retains nothing after the request, but it is a
network call and you should know it happens.

Every call falls back to the on-device model when PCC refuses, is rate limited,
times out or cannot be reached. That fallback carries real weight: both services
build their on-device session with `.permissiveContentTransformations`, because
the default guardrails refuse ordinary journal content and refuse questions
naming real people. `PrivateCloudComputeLanguageModel` exposes no guardrails
setting, so the permissive configuration exists only on the device, and a PCC
refusal is answered there.

`ModelRouter` is the only place that builds a session. Anything that constructs
one directly opts itself out of both PCC and the fallback.

## The four tabs

| Tab | What it is for |
|---|---|
| **Today** | Write or dictate today's entry. The model extracts people, activities, outcomes, hopes, emotions and any decisions inside it. Timeline and Settings open from its toolbar. |
| **Journal** | Read back past days, grouped and filterable by mood. |
| **People** | Everyone your entries mention, with relationships, occupations, preferences, and a map of how they connect. |
| **Ask** | Ask a question about your own history. Answers are grounded in your entries and cite them. |

Timeline sits behind the calendar button on Today. It is the one dated view that
holds everything: events, decisions and entries together, with calendar import
and decisions due to be revisited.

## What makes the Ask tab work

Asking a model about your own life is the part that is easy to get wrong. A
fluent answer that quietly invents a date or a person is worse than no answer.
Several pieces exist only to prevent that:

- **A memory graph.** `MemoryGraphBuilder` turns entries, people, events,
  reminders and decisions into typed nodes and edges. `MemoryGraphRetriever`
  walks it to gather evidence for a question, scoring by person links,
  structured filters, recency and time proximity.
- **Deterministic answers where they are possible.** "When did I last see X" is
  computed as a real maximum over dated evidence, not reasoned out of context
  text by a small model. Some questions never reach the model at all.
- **Guards against invented people.** `UnknownPersonGuard` and
  `WhoIsQuestionDetector` refuse questions about a name the app has never seen,
  instead of letting the model answer from the nearest similar fact.
  `UnresolvedPersonFinder` distinguishes "never heard of them" from "written
  about but never added to People".
- **A grounding check.** `GroundingValidator` and `MemoryGraphContextPacker`
  check the answer against the evidence that was actually supplied.

A debug pane under each answer shows the exact context the model received, and
it is the fastest way to see why an answer looks wrong. It is DEBUG-only, along
with the wipe-data button and the engine log, and their absence from release
builds is checked against the built binary rather than assumed from the source.

## People

People are extracted from entries, so the same person written two ways becomes
two records. A misheard name is the usual cause: "Akil" for "Akhil" creates a
second person, and correcting the spelling leaves two identical ones.

The editor watches for that. When another person matches on first and last name
it offers a merge, naming how many entries the other record holds. Merging moves
entries, relationships, conflicts, reminders and scheduled events onto the
survivor, fills in any profile details the survivor lacks, and keeps the
duplicate's spelling as an alias so older mentions still resolve.

It offers rather than acts. Merging deletes a record, and two people can
legitimately share a name, which is what the context qualifier is for.

## Themes

Seven themes, chosen in Settings. Album, Ink and Dusk are colour only and follow
the system light and dark setting. Night Sky, Ocean, Galaxy and Rain paint a
backdrop behind every screen and keep the appearance their backdrop needs.

The painted ones are drawn, not images. Each is a graded wash, some soft blurred
shapes, and a field generated once from a seeded generator so the sky is the
same sky on every launch. Nothing animates: a twinkle means redrawing a few
hundred shapes behind whatever is being read or typed, for as long as the app is
open.

Adding a theme means adding an `AlbumPalette`. Views read semantic roles such as
`Field.background` and `Button.primaryFill` rather than raw colours, and the
navigation bar goes unfilled under a painted theme so the backdrop runs behind
the title.

## Voice

**Speech to text** is Apple's iOS 26 `SpeechAnalyzer` and `SpeechTranscriber`,
on device, streaming partial results as you speak.

Volatile results lag the speaker by about a second, so the last words of a
sentence are still unreported when the mic is tapped off. They arrive in the
final result, after capture has already stopped. Two states exist for this:
`isRecording` is audio capture and goes false immediately, so a mic button is
live again at once; `isTranscribing` stays true through the tail and is what a
view guards on before copying the transcript into a field. Anything that reads
the transcript in order to act on it calls `finishRecording()` and waits.

Whisper `base.en` is implemented and currently withdrawn behind
`SpeechEngine.isOffered`. The preference is refused rather than cleared, so
turning it back on restores each person's own choice.

**Text to speech** is Apple's on-device voice. `SpeechTextSanitizer` strips
markdown before speaking, and ISO dates are rewritten as words on the way out,
so a cited day is read as "Friday 10 July 2026" rather than spelled out with
its dashes.

**Kokoro** through MLX is implemented and currently withdrawn behind
`VoiceEngine.isOffered`, for the same reason Whisper is: a reply read aloud
breaks into noise partway through, and the cause is not yet understood. As with
Whisper the preference is refused rather than cleared, so turning it back on
restores each person's own voice.

## Other things it does

- **Weather-aware advice.** WeatherKit plus MapKit geocoding, so advice about a
  future event knows the forecast. Cached, with a Regenerate option.
- **Health context.** HealthKit supplies sleep, steps and workouts for a day, so
  an entry can be read alongside how you actually slept.
- **Calendar import.** EventKit reads upcoming events into MindLocal's own
  store, upserting by identifier, so they join the timeline and get the same
  grounded advice.
- **Mood trends** over time, and a **How I Decide** view summarising your own
  decision patterns.
- **Reminders and nightly check-ins** through local notifications. The check-in
  asks a few questions aloud, listens, and saves a structured entry.

## Building

```bash
xcodebuild build -project MindLocal.xcodeproj -scheme MindLocal \
  -destination 'generic/platform=iOS' -configuration Debug
```

**Build for a device, not the simulator.** Simulator builds fail to link
mlx-swift's `Cmlx`: `_MTLTensorDomain` and `_MTLIOErrorDomain` are present in
the iphoneos SDK's `Metal.tbd` and absent from the simulator SDK. This also
means the test target cannot run, because XCTest needs a simulator. Do not
assume the tests passed because the code compiled. Test-only logic is best
verified as a standalone `swift` script until that is resolved.

Requirements:

- Xcode 27, iOS 26.0 minimum, iPhone only.
- Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- File-system-synchronized folder groups: any file added under `MindLocal/` is
  compiled automatically and is not listed in the `.pbxproj`.
- Bundle id `com.gayatrikolekar.MindLocal`, display name "The Little Things".
- **Real hardware for AI and speech.** An Apple Intelligence-capable device with
  Apple Intelligence enabled. The simulator reports the on-device model as
  unavailable; `ExtractionService` has a mock path for that case.
- Entitlements: WeatherKit, HealthKit, and Private Cloud Compute. The last is a
  managed entitlement. Without it, `FoundationModels` traps the process rather
  than throwing, so `privateCloudComputeEnabled` and the entitlement move
  together.

Dependencies, both through SPM:

| Package | Used for |
|---|---|
| `argmaxinc/argmax-oss-swift` | WhisperKit, the withdrawn speech-to-text engine |
| `mlalma/kokoro-ios` | Kokoro text-to-speech, withdrawn, with MLX and MisakiSwift |

## Layout

```
MindLocal/
  Models/        19 files. SwiftData models and @Generable extraction targets:
                 Experience, Decision, Person, Event, Reminder, Conflict,
                 Principle, MemoryGraph, and the *Draft types the model fills in
  Services/      49 files. Extraction, retrieval, the memory graph, model
                 routing, speech in both directions, weather, health, calendar,
                 notifications
  ViewModels/    Capture, Advice, JournalConversation
  Views/         35 files. The four tabs, Timeline, settings, and the painted
                 theme backdrops
docs/
  domain-model.md   The north-star spec: episodic vs semantic memory, node and
                    edge taxonomy, the learning loop, and the alignment roadmap
  blog/             Written pieces on how retrieval and grounding work here
MindLocalTests/     9 test files, mostly around retrieval, person resolution,
                    speech chunking and the voice activity detector
```

About 17,000 lines of Swift in the app, plus 3,000 in tests.

## Design principles

**Local first.** The journal never leaves the phone. Generation may, to Private
Cloud Compute, and that is the one place where it does.

**Structure over scale.** A small model is worse at open-ended reasoning than a
large hosted one, so the app compensates with a typed graph, deterministic
computation where it is possible, and refusal where it is not. That structure
still does the work when an answer comes back from PCC.

**A wrong answer with a citation is worse than no answer.** Most of the guard
code exists because of specific failures. The model once answered "Tommy is your
brother" about a name that appeared in no entry. It once put one person's
birthday under another person's name. Each of those is now a test.

**Say "I don't know" cleanly.** An unresolved name, an empty retrieval and a
question outside the corpus each have their own honest answer.

## Known open items

- **Journal is a subset of Timeline.** Journal lists entries; Timeline lists
  entries, events and decisions. Two dated views, one containing the other.
- **Dictation start is slow.** The tail problem is fixed, but the app's mic
  still starts more slowly than the keyboard's, which uses a warm system
  service. The app builds an analyzer, moves the audio session from playback to
  record, and starts the engine on every tap. Measure before optimising: the
  cost is in the start path, not in recognition.
- **Dictation overwrites typed text.** Starting the mic with text already in a
  field replaces it, because the observer assigns the whole transcript. This is
  what stops the keyboard's mic and the app's mic being usable together.
- **Kokoro read-aloud breaks into noise.** A reply plays, turns to static for a
  stretch, then plays again. Measured, so some things are ruled out: synthesis
  runs at 0.15-0.27x real time, so the queue is never starved, and the gaps are
  not playback running dry. The noise is in the samples the model returns.
  Withdrawn until that is understood. `ModelRouter.dumpAudio` writes each
  synthesized chunk to `Documents` as a WAV in debug builds, which is the way
  to look at it rather than reason about it.
- **Whisper VAD thresholds are unmeasured.** `silenceFloor`,
  `confidentSpeechLevel` and `minEnergyVariation` were chosen from published
  dBFS ranges, not measured against a real microphone in a real room. Moot while
  Whisper is withdrawn, and still unmeasured when it returns.
- **PCC refusal rate is unmeasured.** If PCC refuses this content often, the Ask
  path pays its latency and answers on device anyway.
- **Retrieval fixes designed, not built.** Four, all around the case where a
  question names something the app has never seen.

## Privacy

No accounts, no servers of ours, no analytics. Health, calendar, location and
microphone access are each requested only for the feature that needs them, and
that data stays in the app's own store. The one thing that leaves the phone is
text sent to Apple's Private Cloud Compute for generation, described above.
