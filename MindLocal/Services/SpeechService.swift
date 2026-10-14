import Foundation
import Speech
import AVFoundation
import os

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
    /// The complete transcript for one dictation, published once when results
    /// stop arriving, and nil until then.
    ///
    /// Views apply this without checking anything. `isTranscribing` cannot
    /// gate the last update: SwiftUI runs `onChange` after the mutation, so the
    /// final result and the flag going false can land in one pass and the
    /// handler then reads a flag that is already false. What it discarded is
    /// the tail of the sentence and its punctuation, which only the finalized
    /// result carries.
    var finalTranscript: String? { get }
    /// Does the slow, session-independent setup ahead of the tap.
    ///
    /// Everything this covers used to run inside `startRecording`, between the
    /// user tapping the mic and the audio engine starting, so whatever they
    /// said in the meantime was never captured at all. Safe to call repeatedly
    /// and safe to skip: `startRecording` still does the work if it was not
    /// done, it is just slow again.
    func prepare() async
}

extension SpeechServicing {
    /// Engines that have nothing outstanding when capture stops need no more
    /// than the synchronous path.
    func finishRecording() async { stopRecording() }
    var isTranscribing: Bool { isRecording }
    var finalTranscript: String? { nil }
    func prepare() async {}
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
    private(set) var finalTranscript: String?

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?

    /// Resolved once per process. The configuration it depends on is constant,
    /// so renegotiating it per recording bought nothing and cost a round trip
    /// before the microphone was live.
    private static var cachedFormat: AVAudioFormat?

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

    /// Nothing in this path used to say anything, which is why a dictation
    /// that died halfway looked identical to one that was merely slow.
    private static let log = Logger(subsystem: "com.gayatrikolekar.MindLocal",
                                    category: "speech")

    /// Watches for the system taking the microphone away: a call, Siri, an
    /// alarm, another app starting to record. The engine is already stopped by
    /// the time this lands and `SpeechTranscriber.results` ends with it, so
    /// without it the button stays red over text that will never grow again.
    private var interruptionObserver: NSObjectProtocol?

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

    func prepare() async {
        let locale = Locale(identifier: "en-US")
        let probe = Self.makeTranscriber(locale: locale)
        try? await ensureModel(for: probe, locale: locale)
        if Self.cachedFormat == nil {
            Self.cachedFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [probe])
        }
    }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }

    func startRecording() async throws {
        transcript = ""
        finalizedText = ""
        finalTranscript = nil

        let locale = Locale(identifier: "en-US")
        let transcriber = Self.makeTranscriber(locale: locale)
        self.transcriber = transcriber

        // Both of these are no-ops once `prepare()` has run. Left in so a mic
        // tapped before the screen finished appearing still works.
        try await ensureModel(for: transcriber, locale: locale)
        if Self.cachedFormat == nil {
            Self.cachedFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        analyzerFormat = Self.cachedFormat

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
                        Self.log.debug("Finalized \(self.finalizedText.count, privacy: .public) characters")
                    } else {
                        self.transcript = self.append(self.finalizedText, chunk)
                    }
                }
                // Falling out of the loop means the transcriber closed its own
                // stream. After `stopRecording` that is the expected end. While
                // `isRecording` is still true it is the analyzer giving up with
                // the user still talking.
                if self.isRecording {
                    Self.log.error("Transcription stream ended while still recording")
                    self.abandonCapture()
                }
            } catch {
                // Swallowing this is what made the failure look like a hang.
                // The words stopped growing, the mic stayed red, and nothing
                // anywhere said why — on screen or in the log.
                if !Task.isCancelled {
                    Self.log.error("Transcription stream failed: \(error.localizedDescription, privacy: .public)")
                }
                if self.isRecording { self.abandonCapture() }
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
        observeInterruptions()
        Self.log.notice("Capture started")
    }

    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                Self.log.notice("Audio session interrupted; ending capture")
                // Keep what was heard before the interruption. There is no
                // resuming here: the engine is already down and the analyzer's
                // input has ended, so the honest move is to give the user back
                // a mic button they can tap again.
                self.abandonCapture()
            }
        }
    }

    /// Ends capture that the system or the analyzer has already broken.
    ///
    /// Everything transcribed so far is kept — a dictation that dies halfway is
    /// still worth the half. What this must not do is leave `isRecording` true,
    /// which is what pinned the mic button on red with no way back short of
    /// leaving the screen.
    private func abandonCapture() {
        guard isRecording else { return }
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish()
        inputContinuation = nil
        analyzer = nil
        transcriber = nil
        resultsTask = nil
        finalTranscript = transcript
        isTranscribing = false
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
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

            // Hand the audio session back. Recording claimed it as `.record`
            // and nothing ever released it, so the next thing that tried to
            // speak had to switch the category of a session still held for
            // capture. That fails quietly — every call on the playback side is
            // a `try?` — and the result was silence: in the check-in, leaving
            // the mic running and tapping Next meant never hearing the next
            // question read out.
            //
            // After the drain, not before: deactivating mid-finalize would cut
            // the tail of the speech this whole teardown exists to keep.
            if !self.isRecording {
                try? AVAudioSession.sharedInstance()
                    .setActive(false, options: .notifyOthersOnDeactivation)
                self.finalTranscript = self.transcript
                Self.log.notice("Published final \(self.transcript.count, privacy: .public) chars")
                self.isTranscribing = false
            }
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
