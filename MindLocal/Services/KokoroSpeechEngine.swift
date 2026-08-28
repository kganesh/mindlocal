import Foundation
import AVFoundation
import UIKit

#if canImport(KokoroSwift)
import KokoroSwift
import MLX
import MLXUtilsLibrary
#endif

enum KokoroSpeechError: Error {
    case runtimeUnavailable
    case voicesMissing
    case modelMissing
    case voiceNotFound(String)
}

#if canImport(KokoroSwift)

/// All Kokoro model state, confined to one serial queue and loaded lazily.
///
/// Two separate loads, because they cost wildly different amounts and are
/// needed at different times:
///
/// - **voices** (`voices.npz`, 14 MB) — needed to populate the picker.
/// - **model** (`kokoro-v1_0.safetensors`, 327 MB) — needed only to actually
///   speak. `KokoroTTS.init` reads and sanitises the entire file synchronously,
///   so this must never happen anywhere near view construction.
///
/// `@unchecked Sendable`: `KokoroTTS` and `MLXArray` aren't `Sendable`, so they
/// never leave the queue. Only `[String]` and `[Float]` cross back.
private final class KokoroRuntime: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.gayatrikolekar.MindLocal.kokoro",
                                      qos: .userInitiated)
    private let voicesFile: URL

    private var voices: [String: MLXArray]?
    private var tts: KokoroTTS?

    init(voicesFile: URL) {
        self.voicesFile = voicesFile
    }

    /// MLX keeps freed Metal buffers in a cache sized for a Mac by default.
    /// On a phone that cache is the difference between fitting and being
    /// jetsammed, especially with a FoundationModels session still resident
    /// from generating the advice we're about to read aloud.
    private static let boundCache: Void = {
        GPU.set(cacheLimit: 32 * 1024 * 1024)
    }()

    /// Loads the 14 MB voice archive on first ask; cheap enough for Settings.
    func voiceNames() async -> [String] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.loadVoicesIfNeeded()
                    .keys.map { String($0.split(separator: ".")[0]) }
                    .sorted())
            }
        }
    }

    func synthesize(_ text: String, voice: String, modelFile: URL) async throws -> [Float] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let embedding = self.loadVoicesIfNeeded()[voice + ".npy"] else {
                        throw KokoroSpeechError.voiceNotFound(voice)
                    }
                    // The expensive one — first spoken word pays for it, and
                    // only once per launch.
                    _ = Self.boundCache
                    if self.tts == nil { self.tts = KokoroTTS(modelPath: modelFile) }
                    guard let tts = self.tts else { throw KokoroSpeechError.modelMissing }

                    // Voice naming carries the accent: "a…" is American,
                    // everything else British. The wrong one mispronounces
                    // rather than erroring.
                    let language: Language = voice.first == "a" ? .enUS : .enGB
                    let (audio, _) = try tts.generateAudio(voice: embedding,
                                                           language: language,
                                                           text: text)
                    // Intermediates from one chunk are dead by the time the
                    // next is requested; holding them across a whole reply is
                    // what pushes peak usage over the limit.
                    GPU.clearCache()
                    continuation.resume(returning: audio)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Drops cached weights — used when the download is deleted, so a stale
    /// model isn't kept alive by this cache.
    func purge() {
        queue.async {
            self.tts = nil
            self.voices = nil
            GPU.clearCache()
        }
    }

    /// Drops the weights but keeps the voices — the expensive half, released
    /// under memory pressure so the OS doesn't kill the app instead.
    func releaseModel() {
        queue.async {
            self.tts = nil
            GPU.clearCache()
        }
    }

    /// Queue-confined; never call from outside `queue`.
    private func loadVoicesIfNeeded() -> [String: MLXArray] {
        if let voices { return voices }
        let loaded = NpyzReader.read(fileFromPath: voicesFile) ?? [:]
        voices = loaded
        return loaded
    }
}

/// Kokoro text-to-speech, played back chunk by chunk.
///
/// A shared instance rather than one per view: constructing this used to load
/// the model, and `@State private var speaker = SpeechSpeaker()` re-evaluates
/// its initialiser every time a View struct is created. Sharing also means only
/// one thing can be speaking at a time, which is what the app wants anyway.
@MainActor
final class KokoroSpeechEngine: SpeechSynthesizing {

    static let shared = KokoroSpeechEngine()

    static let voicePreferenceKey = "kokoroVoiceId"
    static let defaultVoice = "af_heart"

    static var selectedVoice: String {
        get { UserDefaults.standard.string(forKey: voicePreferenceKey) ?? defaultVoice }
        set { UserDefaults.standard.set(newValue, forKey: voicePreferenceKey) }
    }

    private let runtime: KokoroRuntime?
    private let audioEngine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat?
    private var connected = false

    private var speakTask: Task<Void, Never>?
    private var pendingBuffers = 0
    private var allChunksScheduled = false
    private var onFinish: (() -> Void)?

    /// Cheap: locates the bundled voice archive and builds an audio format.
    /// No file is read and no weights are loaded here.
    private init() {
        if let voicesFile = Bundle.main.url(forResource: "voices", withExtension: "npz") {
            runtime = KokoroRuntime(voicesFile: voicesFile)
        } else {
            runtime = nil
        }
        format = AVAudioFormat(standardFormatWithSampleRate: Double(KokoroTTS.Constants.samplingRate),
                               channels: 1)

        // Give the weights back rather than let the OS kill the app for them.
        // 327 MB of F32 is worth more to iOS than it is to us between replies.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseModelUnderPressure() }
        }
    }

    /// Keeps playback going — only the weights are dropped, and they reload on
    /// the next request.
    private func releaseModelUnderPressure() {
        runtime?.releaseModel()
    }

    /// Voice names for the picker. Loads the 14 MB archive on first call only.
    func voiceNames() async -> [String] {
        await runtime?.voiceNames() ?? []
    }

    /// Forgets cached weights after the download is removed.
    func purge() {
        stop()
        runtime?.purge()
    }

    // MARK: - SpeechSynthesizing

    func speak(_ chunks: [String], onFinish: @escaping () -> Void) {
        guard !chunks.isEmpty else { return onFinish() }
        guard let runtime, let modelFile = KokoroModelStore.shared.modelFile else {
            return onFinish()
        }
        stop()

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio,
                                                         options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        self.onFinish = onFinish
        allChunksScheduled = false
        pendingBuffers = 0

        let voice = Self.selectedVoice
        speakTask = Task { [weak self] in
            for chunk in chunks {
                guard let self, !Task.isCancelled else { return }
                guard let samples = try? await runtime.synthesize(chunk, voice: voice,
                                                                  modelFile: modelFile),
                      !samples.isEmpty else { continue }
                guard !Task.isCancelled else { return }
                self.schedule(samples)
            }
            guard let self, !Task.isCancelled else { return }
            self.allChunksScheduled = true
            self.finishIfDrained()
        }
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        onFinish = nil
        pendingBuffers = 0
        allChunksScheduled = false
        if player.isPlaying { player.stop() }
        if audioEngine.isRunning { audioEngine.stop() }
    }

    // MARK: - Playback

    private func schedule(_ samples: [Float]) {
        guard let format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            UnsafeMutableRawPointer(channel)
                .copyMemory(from: UnsafeRawPointer(base),
                            byteCount: source.count * MemoryLayout<Float>.stride)
        }

        // Attach on first use rather than in init, so a launch that never
        // speaks never touches the audio graph.
        if !connected {
            audioEngine.attach(player)
            audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
            connected = true
        }
        if !audioEngine.isRunning {
            do { try audioEngine.start() } catch { return }
        }

        pendingBuffers += 1
        // `.dataPlayedBack` fires when the audio was actually heard, not when
        // it left the queue — that's when the UI's stop button should revert.
        player.scheduleBuffer(buffer, at: nil, options: [],
                              completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.bufferPlayed() }
        }
        if !player.isPlaying { player.play() }
    }

    private func bufferPlayed() {
        guard pendingBuffers > 0 else { return }
        pendingBuffers -= 1
        finishIfDrained()
    }

    private func finishIfDrained() {
        guard allChunksScheduled, pendingBuffers == 0, let finish = onFinish else { return }
        onFinish = nil
        if audioEngine.isRunning { audioEngine.stop() }
        finish()
    }
}

#endif
