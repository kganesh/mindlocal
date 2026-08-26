import Foundation
import AVFoundation

#if canImport(WhisperKit)
import WhisperKit
#endif

enum WhisperSpeechError: Error {
    /// The WhisperKit package isn't linked into this build.
    case runtimeUnavailable
    /// Mic input couldn't be converted to the 16 kHz mono float Whisper needs.
    case audioFormatUnavailable
}

/// Thread-safe accumulator for mic audio.
///
/// The audio tap runs on a realtime thread while the service reads from the
/// main actor, so the samples can't live on the `@MainActor`-isolated service
/// itself. Kept deliberately small: a lock and an array, nothing that can block
/// the audio thread for long.
private final class SampleBuffer: @unchecked Sendable {
    private var samples: [Float] = []
    private let lock = NSLock()

    var count: Int {
        lock.withLock { samples.count }
    }

    func append(_ incoming: [Float]) {
        lock.withLock { samples.append(contentsOf: incoming) }
    }

    func snapshot() -> [Float] {
        lock.withLock { samples }
    }

    /// Drops everything before `index`, returning what was dropped.
    func drain(upTo index: Int) -> [Float] {
        lock.withLock {
            let cut = min(index, samples.count)
            let head = Array(samples[..<cut])
            samples.removeFirst(cut)
            return head
        }
    }

    func removeAll() {
        lock.withLock { samples.removeAll(keepingCapacity: true) }
    }
}

/// Whisper `base.en` speech-to-text, drop-in for `SpeechService`.
///
/// Whisper is not a streaming model: it consumes a 30-second window and emits
/// text for the whole window at once. Live results are approximated by keeping
/// mic audio in a 16 kHz buffer and re-transcribing the accumulated window on a
/// timer, replacing `transcript` each pass. Re-running the whole window rather
/// than appending is deliberate — Whisper's reading of a phrase improves as the
/// rest of the sentence arrives, so later passes correct earlier ones instead
/// of compounding them.
///
/// `base.en` over `tiny.en` for one reason above accuracy: tiny hallucinates on
/// near-silence far more readily, and users pause mid-sentence constantly here.
/// The `VoiceActivityDetector` gate handles the rest.
@Observable
final class WhisperSpeechService: SpeechServicing {

    private(set) var transcript: String = ""
    private(set) var isRecording: Bool = false

    /// WhisperKit model identifier. `.en` beats multilingual `base` on English
    /// by a clear margin; switch to `"base"` only if non-English capture is
    /// added, and re-tune the VAD thresholds if so.
    static let modelName = "base.en"

    private static let sampleRate: Double = 16_000
    /// Whisper's fixed input window. Audio past this must be committed.
    private static let windowSamples = Int(30 * sampleRate)
    /// Floor on the refresh cadence — inference is the real limit, see `nextInterval`.
    private static let minRefreshInterval: TimeInterval = 1.2
    /// How far back to hunt for a silence to cut on when the window fills.
    private static let boundarySearchWindow: TimeInterval = 4

    private let audioEngine = AVAudioEngine()
    private let buffer = SampleBuffer()
    private let vad = VoiceActivityDetector()
    private var refreshTask: Task<Void, Never>?

    /// Text for windows already committed. Never re-transcribed, so a long
    /// recording costs the same per pass as a short one.
    private var committedText = ""

    /// Wall-clock cost of the last transcribe call, used to pace the refresh
    /// loop. `base.en` runs roughly 2× tiny, and on older hardware a fixed
    /// cadence would queue passes faster than they complete.
    private var lastInferenceSeconds: TimeInterval = 0.4

    #if canImport(WhisperKit)
    private var whisper: WhisperKit?
    #endif

    // MARK: - SpeechServicing

    /// Whisper needs the microphone only — no speech-recognition entitlement,
    /// and one fewer permission prompt than `SpeechService`.
    func requestAuthorization() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startRecording() async throws {
        #if canImport(WhisperKit)
        transcript = ""
        committedText = ""
        buffer.removeAll()

        // First call loads and compiles the model. Doing it before the engine
        // starts keeps the opening words out of a buffer nothing is draining.
        if whisper == nil {
            whisper = try await WhisperKit(WhisperKitConfig(model: Self.modelName))
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = audioEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                sampleRate: Self.sampleRate,
                                                channels: 1,
                                                interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: whisperFormat)
        else { throw WhisperSpeechError.audioFormatUnavailable }

        let sink = buffer
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { pcm, _ in
            guard let converted = Self.convert(pcm, using: converter, to: whisperFormat),
                  let channel = converted.floatChannelData?[0] else { return }
            sink.append(Array(UnsafeBufferPointer(start: channel,
                                                  count: Int(converted.frameLength))))
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = await self?.nextInterval() else { return }
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
        #else
        throw WhisperSpeechError.runtimeUnavailable
        #endif
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        refreshTask?.cancel()
        refreshTask = nil

        // One last pass so the tail since the previous refresh isn't lost.
        Task { await refresh(final: true) }
    }

    // MARK: - Transcription loop

    /// Never schedules passes faster than inference completes, or the loop
    /// falls further behind the longer someone talks.
    private func nextInterval() -> TimeInterval {
        max(Self.minRefreshInterval, lastInferenceSeconds * 1.5)
    }

    private func refresh(final: Bool = false) async {
        let window = buffer.snapshot()

        // A window past Whisper's limit has to be committed before it grows
        // further. Cut on the quietest point in the recent past so the split
        // doesn't land mid-syllable; hard-cut if the tail is uniformly loud,
        // since waiting isn't an option once the model's window is full.
        if window.count >= Self.windowSamples {
            let cut = vad.quietestBoundary(in: window,
                                           searchingLast: Self.boundarySearchWindow,
                                           sampleRate: Self.sampleRate)
                ?? Self.windowSamples
            let head = buffer.drain(upTo: cut)
            let text = await transcribe(head)
            committedText = Self.join(committedText, text)
            transcript = committedText
            return
        }

        // Below a second there isn't enough context for a useful pass, and the
        // partial word at the end tends to come back wrong anyway.
        guard final || window.count >= Int(Self.sampleRate) else { return }

        let text = await transcribe(window)
        transcript = Self.join(committedText, text)
    }

    /// Runs the model, but only on audio the VAD believes contains speech.
    ///
    /// This gate is the point of the whole class. Whisper fed room tone returns
    /// confident filler rather than an empty string, and there is no confidence
    /// signal in the result that reliably separates the two after the fact.
    private func transcribe(_ audio: [Float]) async -> String {
        guard vad.containsSpeech(audio) else { return "" }

        #if canImport(WhisperKit)
        guard let whisper else { return "" }
        let started = Date()
        let results = try? await whisper.transcribe(audioArray: audio)
        lastInferenceSeconds = Date().timeIntervalSince(started)

        return results?
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        #else
        return ""
        #endif
    }

    // MARK: - Helpers

    static func join(_ base: String, _ addition: String) -> String {
        let b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { return a }
        if a.isEmpty { return b }
        return b + " " + a
    }

    /// Converts a mic buffer to Whisper's format. Runs on the audio thread.
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
