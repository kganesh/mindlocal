# MindLocal

A private, on-device iPhone app for capturing **decisions** — record a voice note
about a choice you're making, and an on-device Foundation Model (Apple Intelligence)
extracts the structured decision (options considered, stakes, domain) for later recall
and outcome tracking. No accounts, no cloud. (Formerly scaffolded as "DecisionMemory";
renamed to MindLocal — the `…Local` family with ResumeLocal / LingoLocal.)

This is the **Milestone 1 (Capture)** scaffold from the spec. See `README.md` for the
full setup notes, file map, M1 acceptance criteria, and "known items to verify".

## Build & run

```bash
xcodebuild build -project MindLocal.xcodeproj -scheme MindLocal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug
```

- Single target/scheme: `MindLocal`. iPhone only, **iOS 26.0** minimum, Swift 5 language
  mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- Uses **file-system-synchronized folder groups**: any file added under `MindLocal/` is
  compiled automatically (not listed in the `.pbxproj`).
- Bundle id `com.gayatrikolekar.MindLocal`. Speech/mic usage strings are set via
  `INFOPLIST_KEY_NS…UsageDescription` build settings (generated Info.plist).
- **AI + speech need real hardware**: an Apple Intelligence–capable device (or Apple
  Silicon Mac running the app) with Apple Intelligence enabled. The simulator builds but
  on-device model/transcription report unavailable; `ExtractionService` has a mock path.

## Architecture (`MindLocal/`)

```
MindLocalApp.swift        @main; SwiftData modelContainer(Decision, OptionConsidered, Outcome)
Prompts.swift             All extraction prompts (spec §10)
Models/
  Decision.swift          SwiftData @Model: Decision, OptionConsidered, Outcome
  DecisionDraft.swift     @Generable extraction target for guided generation
  Enums.swift             Domain, Stakes, OutcomeResult
Services/
  ExtractionService.swift On-device FoundationModels guided generation (+ mock)
  SpeechService.swift     SFSpeechRecognizer wrapper (on-device transcription)
  DraftStore.swift        Crash-safe transcript persistence
ViewModels/
  CaptureViewModel.swift  Capture flow state machine
Views/
  RootView.swift          Availability gate (Apple Intelligence)
  CaptureView / DraftPreviewView / DecisionListView / DecisionDetailView
```

Design: SwiftUI + `@Observable`, SwiftData for storage, `FoundationModels`
(`LanguageModelSession` + `@Generable`) for extraction behind a service protocol so the
model/speech backends are swappable and testable.

## Notes / to verify on device (from README)
- `LanguageModelSession(model:instructions:)` init shape; `@Guide` syntax on arrays.
- Consider migrating `SpeechService` to iOS 26 `SpeechAnalyzer`/`SpeechTranscriber`.
- `SystemLanguageModel.Availability` unknown-case handling.
- M1 not yet covered: extraction-latency (≤3s) measurement + model-downloading queue path.
