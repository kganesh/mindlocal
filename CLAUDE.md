# InnerSage

A private iPhone journal. You write or speak about your day, a Foundation Model
extracts structure from it (people, activities, outcomes, decisions), and you can
ask questions about your own history later. Storage is local-only and there is no
backend.

Model work is on-device today. `ModelRouter` can route generation to Private
Cloud Compute, but the path is gated off behind `privateCloudComputeEnabled`
pending Apple's managed entitlement — see "Model routing" below before turning
it on.

See `README.md` for what the app does and `docs/domain-model.md` for the
north-star spec. This file covers what you need to know to work in the code.

> Scaffolded as "DecisionMemory", shipped as MindLocal, now InnerSage. The
> target, scheme, module, source folder and bundle id all still read
> `MindLocal` and are staying that way: the bundle id is bound to an uploaded
> build, and the rest is internal. Only the display name and user-facing text
> changed. Decisions are now one kind of journal entry among several, not the
> whole product, so older documents and some type names still use the original
> framing.

## Build and run

**Build for a device. Simulator builds do not link.**

```bash
xcodebuild build -project MindLocal.xcodeproj -scheme MindLocal \
  -destination 'generic/platform=iOS' -configuration Debug
```

As of Xcode 26.4, the simulator link fails on mlx-swift's `Cmlx`:
`_MTLTensorDomain` and `_MTLIOErrorDomain` exist in the iphoneos SDK's
`Metal.tbd` and not in `iPhoneSimulator26.4.sdk`. This was masked for months by
stale artefacts in `Debug-iphonesimulator`, so it only appears on a clean build.

**Consequence: the test target cannot run**, because XCTest needs a simulator.
Verify test-only logic by extracting it into a standalone `swift` script instead.
Do not assume `MindLocalTests` passed just because the code compiles.

A second, unrelated blocker: KokoroSwift and MisakiSwift both declare
`resources: [.copy("../../Resources/")]`, which produces a bundle CFBundle reads
as an old-style layout, and `codesign` rejects it. Worked around locally by
seeding an `Info.plist` into each checkout's `Resources/` directory under
DerivedData. SPM re-resolution wipes that. The real fix is `.process` upstream.

To install on a connected device:

```bash
xcodebuild -project MindLocal.xcodeproj -scheme MindLocal -configuration Debug \
  -destination 'id=<device-id>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <device-id> \
  ~/Library/Developer/Xcode/DerivedData/MindLocal-*/Build/Products/Debug-iphoneos/MindLocal.app
```

`xcrun devicectl list devices` gives the id. Note that `log stream --device` no
longer exists on current macOS; device logs need Console.app.

## Project conventions

- Single target and scheme, `MindLocal`. iPhone only, iOS 26.0 minimum.
- Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so
  types are main-actor isolated unless they say otherwise. Watch for this when
  writing anything that touches an audio thread.
- **File-system-synchronized folder groups.** Any file added under `MindLocal/`
  compiles automatically. It is not listed in the `.pbxproj`, so do not edit
  the project file to add a source file.
- Bundle id `com.gayatrikolekar.MindLocal`. Usage strings come from
  `INFOPLIST_KEY_NS…UsageDescription` build settings, not a checked-in plist.
- Entitlements: WeatherKit and HealthKit.
- **AI and speech need real hardware.** An Apple Intelligence-capable device with
  Apple Intelligence enabled. `ExtractionService` has a mock path for when the
  model reports unavailable.

## Architecture

SwiftUI with `@Observable`, SwiftData for storage, `FoundationModels`
(`LanguageModelSession` plus `@Generable`) for extraction and answering.

```
MindLocalApp.swift     @main, .modelContainer(SharedStore.container)
Prompts.swift          Extraction and answering prompts
Models/                SwiftData @Model types and @Generable draft types
Services/              50 files: extraction, retrieval, memory graph, speech,
                       weather, health, calendar, notifications
ViewModels/            Capture, Advice, JournalConversation
Views/                 27 views across four tabs, plus settings
```

**Five protocol seams.** Depend on these, not on concrete types:

| Protocol | Implementations |
|---|---|
| `SpeechServicing` | `SpeechService` (Apple) |
| `SpeechSynthesizing` | `SystemSpeechEngine`, `KokoroSpeechEngine` |
| `ExtractionServicing` | `ExtractionService`, plus a mock |
| `AdvisingServicing` | `AdviceService` |
| `WeatherProviding` | `WeatherService` |

`SpeechEngine.make()` and `VoiceEngine.current` choose the implementation from
the user's setting and from whether the model weights are actually present.

**Engine selection is a known trap.** `SpeechEngine.make()` is a default
argument on the view model initialisers, so it runs once, when the view model is
built. A view model outlives a Settings change. Each of the three view models has
a `syncEngine()` for this, called on the mic path. If you add a fourth, it needs
the same. Note also that `SpeechEngine.currentEngineName` reports the
*preference*, which can differ from the engine an existing view model is holding.

## Model routing

`ModelRouter` and `RoutedSession` (`Services/ModelRouter.swift`) sit between the
services and `LanguageModelSession`. Nothing else constructs a session directly —
keep it that way, or a call site silently opts out of both PCC and the fallback.

PCC is **off** by default. `privateCloudComputeEnabled` must be flipped to
`true` in the same change that adds `com.apple.developer.private-cloud-compute`
to `MindLocal.entitlements` — the two move together, and the flag exists because
PCC traps the process (SIGTRAP) on an unentitled app rather than failing
gracefully, `isAvailable` is itself the crash, and iOS has no runtime entitlement
probe (`SecTaskCopyValueForEntitlement` is macOS-only). Once on, PCC is used
whenever `PrivateCloudComputeLanguageModel().isAvailable`, for its 32K context
window against the on-device ~4K. It falls back to the on-device
model on `.guardrailViolation`, `.refusal`, `.rateLimited`, `.concurrentRequests`
and any `PrivateCloudComputeLanguageModel.Error` (network, daily quota, service
down). It deliberately does not retry `decodingFailure`, `unsupportedGuide` or
`exceededContextWindowSize`: those are properties of the prompt and fail the same
way on either model.

**Why the fallback carries weight.** Both services build their
`SystemLanguageModel` with `.permissiveContentTransformations`, because the
default guardrails refuse ordinary journal content and refuse questions naming
real people — the app's primary query shape (see the comment on
`AdviceService.answerModel`). `PrivateCloudComputeLanguageModel` has one
zero-argument initialiser and exposes no guardrails setting, so that policy
cannot be relaxed for PCC. Refusals land on the on-device model, which still
holds the permissive configuration.

**Unmeasured.** The missing guardrails parameter is an API fact; how often PCC
actually refuses this content is not. If it refuses often, the Advise path pays
PCC latency and answers on-device anyway, and routing Advise through PCC stops
earning its keep. Measure on a device — ask a "who is <name>" question and watch
whether it falls back — before trusting the arrangement.

**`RoutedSession` is single-shot.** A refusal retries on a *fresh* on-device
session, so a multi-turn transcript would not survive it. Every current call site
is single-shot. Anything needing continuity must hold a real
`LanguageModelSession`.

**Eligibility.** PCC for third-party apps requires App Store Small Business
Program enrolment, under 2M first-time downloads, and an application to Apple.

## The Advise path

This is where most of the care is. A fluent answer that invents a date or a
person is worse than no answer, and most of the code here exists because of a
specific failure that got shipped once.

Order of operations in `AdviceView`, and why:

1. `extractIntent` reads what the question is asking for.
2. `PersonContextBuilder.mentionedPeople` resolves named people to their profiles.
3. A `who_is` question routes to `askWhoIs`, which answers from the People
   profile alone or refuses. It never falls through to the general pipeline.
   Falling through is what once produced "Tommy is your brother" for a name that
   appeared in no entry.
4. `WhoIsQuestionDetector` is a backstop for when the classifier misses, because
   the classifier's failure fallback is the unsafe path.
5. `UnknownPersonGuard` refuses questions that merely *mention* an unknown
   person while asking about something else. Its last gate matters: a name the
   graph holds in any form (a project, a place) is not refused.
6. `MemoryQueryResolver` resolves a time window that gates both context paths.
7. Structured retrieval, then semantic retrieval, then the memory graph.
8. `GroundingValidator` checks the answer against what was supplied.

**Do not shortcut these.** If you are tempted to let a question through to the
model because the guard feels over-cautious, look at
`MindLocalTests/UnknownPersonGuardWideningTests.swift` first.

`MemoryGraphRetriever` scoring lives in one function with commented weights.
Read the comment about `neighborBoost` values landing twice per record before
tuning any of them.

## Known open items

- **Dictation drops the end of what you say — fixed, but read this before
  touching the speech path.** `SpeechTranscriber`'s volatile results lag the
  speaker by about a second, so the last words are still unreported when the
  mic is tapped off; they arrive only in the final result, after
  `stopRecording` has returned. Two separate bugs followed from that. The views
  guarded their transcript observer on `isRecording`, which is false by then —
  hence `isTranscribing`, which stays true through the tail and is what a view
  must guard on. And anything that reads `transcript` in order to *act* on it
  must call `finishRecording()`, not `stopRecording()`: Next, Finish, submit
  and send all used to read a second-old transcript. Do not add a synchronous
  read of `transcript` after a stop; that was the third instance of the same
  mistake.
- **Dictation still feels slower than the keyboard's mic, and that part is
  real.** Tapping the keyboard's dictation button uses iOS system dictation, a
  warm service. The app's mic builds a `SpeechAnalyzer`, swings the audio
  session from `.playback` to `.record` and starts the engine on every tap —
  and in the check-in, on every question. `requestAuthorization` is also called
  each time. Measure before optimising, but the cost is in the start path, not
  in recognition.
- **`matchesText` in `MemoryGraphRetriever` keeps only words of four or more
  characters**, so a short subject is dropped from retrieval entirely and common
  words like "when", "that", "last" and "time" drive the search instead.
- **`NLTagger` mislabels short capitalised tokens** as `PlaceName`, which
  silently disables `UnknownPersonGuard` for them.

## Working style in this repo

- Comments explain *why*, not what. Several describe the specific failure that
  motivated the code. Keep that when editing near them.
- Plain English in comments and docs: short sentences, no idioms, the main point
  first. Technical terms stay precise.
- Commits: no `Co-Authored-By` or session trailers. Author as the user.
