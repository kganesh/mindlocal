import Foundation
import Speech
import AVFoundation

protocol SpeechServicing: AnyObject {
    var transcript: String { get }
    /// Audio is being captured right now. This is what a mic button reads: it
    /// goes false the instant capture stops, so the button is live again
    /// immediately.
    var isRecording: Bool { get }
    /// Results are still arriving. Stays true through the tail of the speech,
    /// after capture has stopped. This is what a view reads before copying
    /// `transcript` into a field — the last second of speech lands here.
    var isTranscribing: Bool { get }
    func requestAuthorization() async -> Bool
    func startRecording() async throws
    func stopRecording()
    /// Stops and does not return until the final transcript has landed in
    /// `transcript`. Anything that reads the transcript in order to act on it —
    /// saving an answer, submitting a question — has to use this: `stopRecording`
    /// returns while the tail of the speech is still being transcribed, so a
    /// synchronous read afterwards gets the text as it stood a second ago.
    func finishRecording() async
}

extension SpeechServicing {
    /// Engines that have nothing outstanding when capture stops need no more
    /// than the synchronous path.
    func finishRecording() async { stopRecording() }
    var isTranscribing: Bool { isRecording }
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
    private(set) var isTranscribing: Bool = false

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?

    /// Accumulated finalized text (never rewritten by later results).
    private var finalizedText: String = ""
    /// The teardown started by `stopRecording`, so `finishRecording` can wait
    /// on the same work rather than starting a second one.
    private var teardownTask: Task<Void, Never>?

    /// Locales whose transcription assets have been confirmed installed during
    /// this launch. The two inventory queries in `ensureModel` are a round trip
    /// each and run before any audio is captured, so repeating them on every
    /// mic tap is latency paid at exactly the wrong moment. The answer only
    /// changes if someone removes the assets in Settings mid-session, which
    /// costs one failed start and is corrected on the next launch.
    private static var verifiedLocales: Set<String> = []

    /// Granted permissions cannot be revoked without the app being killed, so
    /// the answer is asked for once and remembered. The check-in requested both
    /// permissions again before every question, and those round trips sit
    /// between the question being read aloud and the mic going live — which is
    /// the gap the first words of an answer fall into.
    private static var authorized = false

    func requestAuthorization() async -> Bool {
        if Self.authorized { return true }

        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        Self.authorized = speechOK && micOK
        return Self.authorized
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
        isTranscribing = true
    }

    /// Stops capture immediately and keeps transcribing the tail.
    ///
    /// Volatile results lag the speaker by around a second, so the last thing
    /// said is usually still unreported when the mic is tapped off — it arrives
    /// only in the final result, which `finalizeAndFinishThroughEndOfInput`
    /// produces after this method returns. `isTranscribing` covers that window
    /// so the views keep copying the transcript; `isRecording` goes false now,
    /// so the mic button can be tapped again without waiting for the tail.
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish()
        inputContinuation = nil

        let analyzer = self.analyzer
        teardownTask = Task { [weak self] in
            guard let self else { return }
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()

            // Wait for the consumer to finish rather than cancelling it: the
            // stream ends on its own once the analyzer finishes, and cancelling
            // first is what would cut off the chunk we waited for. Bounded, so
            // a finalize that throws cannot leave the button stuck on red.
            let drain = self.resultsTask
            let deadline = Task {
                try? await Task.sleep(for: .seconds(2))
                drain?.cancel()
            }
            await drain?.value
            deadline.cancel()

            self.resultsTask = nil
            self.analyzer = nil
            self.transcriber = nil
            // Only if nothing has started again in the meantime, or this would
            // switch off a session that is already capturing.
            if !self.isRecording { self.isTranscribing = false }
        }
    }

    func finishRecording() async {
        stopRecording()
        await teardownTask?.value
    }

    // MARK: - Helpers

    private func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let target = locale.identifier(.bcp47)
        if Self.verifiedLocales.contains(target) { return }

        let supported = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
        guard supported.contains(target) else { throw SpeechError.localeNotSupported }

        let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        if installed.contains(target) {
            Self.verifiedLocales.insert(target)
            return
        }

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        Self.verifiedLocales.insert(target)
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
