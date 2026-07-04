# Decision Memory — M1 Scaffold

Milestone 1 (Capture) source for the app defined in `decision-app-v1-spec.md`. Written against Apple's current Foundation Models docs but **not compiled** — expect minor fixes on first build.

## Setup

1. Xcode 26 → New Project → iOS App, name `DecisionMemory`, interface SwiftUI, storage None (SwiftData is set up in code). Minimum deployment: iOS 26.0.
2. Drag the `Models/`, `Services/`, `ViewModels/`, `Views/` folders plus `DecisionMemoryApp.swift` and `Prompts.swift` into the project (replace the generated App/ContentView files).
3. Add Info.plist keys:
   - `NSSpeechRecognitionUsageDescription` — "Transcribes your voice notes on-device."
   - `NSMicrophoneUsageDescription` — "Records voice notes for decision capture."
4. Run on an Apple Intelligence–capable device or Apple Silicon Mac simulator with Apple Intelligence enabled.

## File map

| Path | Purpose |
|---|---|
| `DecisionMemoryApp.swift` | Entry point, SwiftData container |
| `Models/Decision.swift` | SwiftData models (Decision, OptionConsidered, Outcome) |
| `Models/DecisionDraft.swift` | `@Generable` extraction target |
| `Models/Enums.swift` | Domain, Stakes, OutcomeResult |
| `Prompts.swift` | All prompts (spec §10) |
| `Services/ExtractionService.swift` | On-device guided generation + mock |
| `Services/SpeechService.swift` | On-device SFSpeechRecognizer wrapper |
| `Services/DraftStore.swift` | Crash-safe transcript persistence |
| `ViewModels/CaptureViewModel.swift` | Capture flow state machine |
| `Views/` | RootView (availability gate), Capture, Preview, List, Detail |

## Known items to verify on first build

- `LanguageModelSession(model:instructions:)` — confirmed to exist as `init(model:tools:instructions:)`; check whether `instructions:` takes `String` directly or an `Instructions` builder.
- `@Guide` attribute syntax on array-of-Generable properties.
- Consider migrating `SpeechService` to the newer `SpeechAnalyzer`/`SpeechTranscriber` API (iOS 26) — protocol boundary makes this a drop-in swap.
- `SystemLanguageModel.Availability` unknown-case handling (`case .unavailable(let other)`).

## M1 acceptance criteria

See spec §11 — run through them before calling M1 done. Not yet covered by this scaffold: extraction-latency measurement (≤3s) and the model-downloading queue path (currently just shows status text).
