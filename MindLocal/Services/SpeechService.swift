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

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true   // privacy + offline (spec §7)
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.transcript = result.bestTranscription.formattedString
            }
            if error != nil || (result?.isFinal ?? false) {
                self.cleanup()
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func stopRecording() {
        request?.endAudio()
        cleanup()
    }

    private func cleanup() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        isRecording = false
    }
}
