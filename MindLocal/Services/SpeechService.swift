import Foundation
import Speech
import AVFoundation

protocol SpeechServicing: AnyObject {
    var transcript: String { get }
    var isRecording: Bool { get }
    func requestAuthorization() async -> Bool
    func startRecording() async throws
    func stopRecording()
}

enum SpeechError: Error {
    case notAuthorized
    case recognizerUnavailable
    case localeNotSupported
}

/// On-device speech-to-text using the iOS 26 SpeechAnalyzer / SpeechTranscriber
/// API (spec §2, §7). Unlike SFSpeechRecognizer, this reports *volatile* (live)
/// vs *finalized* results and never rewrites finalized text, so pauses never
/// erase earlier content. The live `transcript` is finalized text + the current
/// volatile chunk.
@Observable
final class SpeechService: SpeechServicing {
    private(set) var transcript: String = ""
    private(set) var isRecording: Bool = false

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?

    /// Accumulated finalized text (never rewritten by later results).
    private var finalizedText: String = ""

    func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        return speechOK && micOK
    }

    func startRecording() async throws {
        transcript = ""
        finalizedText = ""

        let locale = Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        try await ensureModel(for: transcriber, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        // Consume transcription results (runs on the main actor via the enclosing
        // isolation, so @Observable updates are safe).
        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let chunk = String(result.text.characters)
                    if result.isFinal {
                        self.finalizedText = self.append(self.finalizedText, chunk)
                        self.transcript = self.finalizedText
                    } else {
                        self.transcript = self.append(self.finalizedText, chunk)
                    }
                }
            } catch {
                // Stream ended with an error; keep what we have.
            }
        }

        // Audio session + engine → feed converted buffers into the analyzer.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let (inputSequence, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputContinuation = continuation

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let outFormat = analyzerFormat
        let converter = outFormat.map { AVAudioConverter(from: inputFormat, to: $0) } ?? nil

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            if let converter, let outFormat,
               let converted = Self.convert(buffer, using: converter, to: outFormat) {
                continuation.yield(AnalyzerInput(buffer: converted))
            } else {
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        try await analyzer.start(inputSequence: inputSequence)
        isRecording = true
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish()
        inputContinuation = nil

        let analyzer = self.analyzer
        Task {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
            self.resultsTask?.cancel()
            self.resultsTask = nil
            self.analyzer = nil
            self.transcriber = nil
        }
    }

    // MARK: - Helpers

    private func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let target = locale.identifier(.bcp47)
        let supported = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
        guard supported.contains(target) else { throw SpeechError.localeNotSupported }

        let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        if installed.contains(target) { return }

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    /// Joins finalized chunks with a single space.
    private func append(_ base: String, _ chunk: String) -> String {
        let b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { return c }
        if c.isEmpty { return b }
        return b + " " + c
    }

    /// Converts a mic buffer to the analyzer's format. Runs on the audio thread.
    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer,
                                            using converter: AVAudioConverter,
                                            to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var supplied = false
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }
}
