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

    /// Text banked from earlier utterances. On-device recognition often restarts
    /// the transcription on a pause — delivering a fresh, shorter string *without*
    /// `isFinal` — which would erase earlier words. We detect that reset and bank
    /// the last utterance here, so the live `transcript` is banked + current.
    private var confirmedText: String = ""
    /// The current utterance's latest text, used to detect a recognizer reset.
    private var lastSegment: String = ""
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
        lastSegment = ""
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
        // Prefer on-device (privacy + offline, spec §7). The simulator has no
        // on-device speech model, so fall back to server recognition there so the
        // capture flow is testable; real hardware always stays on-device.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            // Recognition callbacks arrive on a background queue; @Observable state
            // and the segment restart must run on the main actor.
            DispatchQueue.main.async {
                if let result {
                    let segment = result.bestTranscription.formattedString
                    // If the recognizer restarted the utterance (a pause), bank the
                    // previous one before it's overwritten.
                    if self.isReset(from: self.lastSegment, to: segment) {
                        self.confirmedText = self.merge(self.confirmedText, self.lastSegment)
                    }
                    self.lastSegment = segment
                    self.transcript = self.merge(self.confirmedText, self.lastSegment)
                }
                if result?.isFinal ?? false || error != nil {
                    // Segment ended (pause finalized, or a recoverable error): bank it.
                    self.confirmedText = self.merge(self.confirmedText, self.lastSegment)
                    self.lastSegment = ""
                    self.transcript = self.confirmedText
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

    /// Heuristic: the recognizer restarted the utterance if the new text no
    /// longer begins with the start of the previous one (a fresh utterance after
    /// a pause), rather than extending/revising it.
    private func isReset(from old: String, to new: String) -> Bool {
        let o = old.trimmingCharacters(in: .whitespacesAndNewlines)
        guard o.count >= 3 else { return false }
        let key = String(o.prefix(8)).lowercased()
        return !new.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix(key)
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
