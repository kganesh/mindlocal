# MindLocal

A private journal for your own life, on your own phone. Write or speak about your
day, and an on-device model turns it into something you can ask questions of
later: who was there, what you decided, how it turned out, what you keep
repeating.

Nothing leaves the device. There are no accounts, no servers and no network
calls in the core loop. The language model, the transcription and the speech
synthesis all run on the phone.

> This started as "DecisionMemory", a scaffold for capturing decisions. It grew
> into a daily journal that still tracks decisions as one kind of entry among
> several. Some older documents still use the original name.

## The four tabs

| Tab | What it is for |
|---|---|
| **Today** | Write or dictate today's entry. The model extracts people, activities, outcomes, hopes, emotions and any decisions inside it. |
| **Journal** | Read back past days. Day-grouped, searchable, with a conversational mode for adding to an entry by voice. |
| **People** | Everyone your entries mention, with relationships, occupations, preferences and a 3D graph of how they connect. |
| **Advise** | Ask a question about your own history. Answers are grounded in your entries and cite them. |

## What makes the Advise tab work

Asking a model about your own life is the part that is easy to get wrong. A
fluent answer that quietly invents a date or a person is worse than no answer.
Several pieces exist only to prevent that:

- **A memory graph.** `MemoryGraphBuilder` turns entries, people, events,
  reminders and decisions into typed nodes and edges.
  `MemoryGraphRetriever` walks it to gather evidence for a question, scoring by
  person links, structured filters, recency and time proximity.
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

There is a debug pane under each answer showing the exact context the model
received. It is DEBUG-only, and it is the fastest way to see why an answer looks
wrong.

## Voice

Both directions are on-device, and both have two engines.

**Speech to text.** Apple's iOS 26 `SpeechAnalyzer` / `SpeechTranscriber` is the
default. It streams word-by-word partial results. **Whisper `base.en`** is
opt-in from Settings, downloads about 142 MB on first enable, and falls back to
Apple's recogniser whenever the weights are not present.

`VoiceActivityDetector` gates every buffer before it reaches Whisper, because
Whisper fed near-silence returns confident filler rather than nothing, and this
app is full of thinking pauses.

**Text to speech.** The system voice by default, or **Kokoro** running through
MLX, opt-in from Settings with its own voice picker. `SpeechTextSanitizer`
strips markdown before speaking, and `SpeechNumberExpander` turns figures into
words so dates and amounts are read correctly.

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
- **Reminders and nightly check-ins** through local notifications.

## Building

```bash
xcodebuild build -project MindLocal.xcodeproj -scheme MindLocal \
  -destination 'generic/platform=iOS' -configuration Debug
```

**Build for a device, not the simulator.** As of Xcode 26.4, simulator builds
fail to link mlx-swift's `Cmlx`: `_MTLTensorDomain` and `_MTLIOErrorDomain` are
present in the iphoneos SDK's `Metal.tbd` and absent from the simulator SDK.
This also means the test target cannot run, because XCTest needs a simulator.
Test-only logic is best verified as a standalone `swift` script until that is
resolved.

Requirements:

- Xcode 26, iOS 26.0 minimum, iPhone only.
- Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- File-system-synchronized folder groups: any file added under `MindLocal/` is
  compiled automatically and is not listed in the `.pbxproj`.
- Bundle id `com.gayatrikolekar.MindLocal`.
- **Real hardware for AI and speech.** An Apple Intelligence-capable device with
  Apple Intelligence enabled. The simulator reports the on-device model as
  unavailable; `ExtractionService` has a mock path for that case.
- Entitlements: WeatherKit and HealthKit.

Dependencies, both through SPM:

| Package | Used for |
|---|---|
| `argmaxinc/argmax-oss-swift` | WhisperKit, the opt-in speech-to-text engine |
| `mlalma/kokoro-ios` | Kokoro text-to-speech, with MLX and MisakiSwift |

## Layout

```
MindLocal/
  Models/        SwiftData models and @Generable extraction targets
                 Experience, Decision, Person, Event, Reminder, Conflict,
                 Principle, MemoryGraph, and the *Draft types the model fills in
  Services/      50 files. Extraction, retrieval, the memory graph, speech in
                 both directions, weather, health, calendar, notifications
  ViewModels/    Capture, Advice, JournalConversation
  Views/         27 views across the four tabs plus settings
docs/
  domain-model.md   The north-star spec: episodic vs semantic memory, node and
                    edge taxonomy, the learning loop, and the alignment roadmap
  blog/             Written pieces on how retrieval and grounding work here
MindLocalTests/     11 test files, mostly around retrieval, person resolution,
                    speech chunking and the voice activity detector
```

About 15,000 lines of Swift, plus 3,000 lines of tests.

## Design principles

**Everything on device.** This is the constraint that shapes the rest. A small
local model is worse at open-ended reasoning than a large hosted one, so the app
compensates with structure: a typed graph, deterministic computation where it is
possible, and refusal where it is not.

**A wrong answer with a citation is worse than no answer.** Most of the guard
code exists because of specific failures. The model once answered "Tommy is your
brother" about a name that appeared in no entry. It once put one person's
birthday under another person's name. Each of those is now a test.

**Say "I don't know" cleanly.** An unresolved name, an empty retrieval and a
question outside the corpus each have their own honest answer.

## Known open items

- **Whisper VAD thresholds are unmeasured.** `silenceFloor`, 
  `confidentSpeechLevel` and `minEnergyVariation` were chosen from published dBFS
  ranges, not measured against a real microphone in a real room. The unit tests
  prove the logic with synthesised tones. They prove nothing about the floor
  being right.
- **Dictation feels slow, cause not confirmed.** Reported under both engines,
  which points away from the engine and towards the shared path. There is a live
  engine and cadence readout under the Advise mic to narrow it down.
- **Retrieval fixes designed, not built.** Four, all around the case where a
  question names something the app has never seen.

## Privacy

No accounts, no servers, no analytics. Health, calendar, location and microphone
access are each requested only for the feature that needs them, and the data
stays in the app's own store.
