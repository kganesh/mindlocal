import Foundation
import Speech
import AVFoundation

protocol SpeechServicing: AnyObject {
    var transcript: String { get }
    var isRecording: Bool { get }
    func requestAuthorization() async -> Bool
    func startRecording() throws
    func stopRecording()
}

enum SpeechError: Error {
    case notAuthorized
    case recognizerUnavailable
}

/// On-device speech-to-text. Uses SFSpeechRecognizer with
/// `requiresOnDeviceRecognition = true` so capture works offline (spec §2).
///
/// NOTE for implementer: iOS 26 introduced the newer SpeechAnalyzer /
/// SpeechTranscriber API with better long-form accuracy. Verify it in current
/// docs (https://developer.apple.com/documentation/speech) and prefer it if
/// stable; this SFSpeechRecognizer implementation is the known-good fallback
/// and the protocol boundary makes swapping trivial.
@Observable
final class SpeechService: SpeechServicing {
    private(set) var transcript: String = ""
    private(set) var isRecording: Bool = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Confirmed text from earlier utterances. On-device recognition finalizes a
    /// segment on each pause (isFinal ends the task); we keep the finalized text
    /// here and start a fresh segment, so the live `transcript` is this plus the
    /// current segment — pauses never erase earlier content.
    private var confirmedText: String = ""
    /// True once the user asked to stop, so a final result tears down instead of
    /// starting another segment.
    private var isStopping: Bool = false

    func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        return speechOK && micOK
    }

    func startRecording() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }
        transcript = ""
        confirmedText = ""
        isStopping = false

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        startSegment()          // create request + task before audio flows
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    /// Begins recognition for the next utterance, reusing the running audio
    /// engine/tap so recording is continuous across pauses.
    private func startSegment() {
        guard let recognizer, !isStopping else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true   // privacy + offline (spec §7)
        request.shouldReportPartialResults = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.transcript = self.merge(self.confirmedText, result.bestTranscription.formattedString)
            }

            if result?.isFinal ?? false || error != nil {
                // Segment ended (pause, or a recoverable error). Keep its text.
                self.confirmedText = self.transcript
                self.task = nil
                self.request = nil
                if self.isStopping {
                    self.finishCleanup()
                } else {
                    self.startSegment()   // continue recording the next utterance
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isStopping = true
        request?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        // The in-flight task delivers its final result and then finishCleanup runs;
        // if there's no task, clean up now.
        if task == nil { finishCleanup() }
    }

    /// Joins confirmed text and the current segment with a single space.
    private func merge(_ base: String, _ segment: String) -> String {
        let b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { return s }
        if s.isEmpty { return b }
        return b + " " + s
    }

    private func finishCleanup() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        isRecording = false
    }
}
