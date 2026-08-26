import Foundation
import AVFoundation

#if canImport(KokoroSwift)
import KokoroSwift
import MLX
import MLXUtilsLibrary
#endif

enum KokoroSpeechError: Error {
    case runtimeUnavailable
    case voicesMissing
    case voiceNotFound(String)
}

#if canImport(KokoroSwift)

/// Confines every MLX touch to one serial queue.
///
/// `KokoroTTS` and the `MLXArray` voice embeddings are not `Sendable`, and
/// synthesis is far too slow to run on the main actor — a long reply would
/// freeze the UI for seconds. Rather than scatter unsafe hops, all model state
/// lives behind this queue and callers `await` it.
private final class KokoroSynthesizer: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.gayatrikolekar.MindLocal.kokoro",
                                      qos: .userInitiated)
    private let tts: KokoroTTS
    private let voices: [String: MLXArray]

    /// Voice names without the `.npy` suffix the archive stores them under.
    var voiceNames: [String] {
        voices.keys.map { String($0.split(separator: ".")[0]) }.sorted()
    }

    init(modelFile: URL, voicesFile: URL) throws {
        guard let loaded = NpyzReader.read(fileFromPath: voicesFile), !loaded.isEmpty else {
            throw KokoroSpeechError.voicesMissing
        }
        voices = loaded
        tts = KokoroTTS(modelPath: modelFile)
    }

    func synthesize(_ text: String, voice: String) async throws -> [Float] {
        guard let embedding = voices[voice + ".npy"] else {
            throw KokoroSpeechError.voiceNotFound(voice)
        }
        // Voice naming carries the accent: "a…" is American, everything else
        // is British. Passing the wrong one mispronounces without erroring.
        let language: Language = voice.first == "a" ? .enUS : .enGB

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let (audio, _) = try self.tts.generateAudio(voice: embedding,
                                                                language: language,
                                                                text: text)
                    continuation.resume(returning: audio)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Kokoro text-to-speech, played back chunk by chunk.
///
/// The point of the chunking is latency: synthesis of chunk *n+1* overlaps
/// playback of chunk *n*, so speech starts after the first sentence rather
/// than after the whole reply. `AVAudioPlayerNode` queues the buffers, so the
/// seams are gapless as long as synthesis keeps ahead of playback — which it
/// does comfortably at roughly 3× real time.
@MainActor
final class KokoroSpeechEngine: SpeechSynthesizing {

    static let voicePreferenceKey = "kokoroVoiceId"
    static let defaultVoice = "af_heart"

    private let synthesizer: KokoroSynthesizer
    private let audioEngine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat

    private var speakTask: Task<Void, Never>?
    /// Buffers scheduled but not yet played out.
    private var pendingBuffers = 0
    /// True once every chunk has been handed to the player.
    private var allChunksScheduled = false
    private var onFinish: (() -> Void)?

    var voiceNames: [String] { synthesizer.voiceNames }

    static var selectedVoice: String {
        get { UserDefaults.standard.string(forKey: voicePreferenceKey) ?? defaultVoice }
        set { UserDefaults.standard.set(newValue, forKey: voicePreferenceKey) }
    }

    init(modelFile: URL) throws {
        guard let voicesFile = Bundle.main.url(forResource: "voices", withExtension: "npz") else {
            throw KokoroSpeechError.voicesMissing
        }
        synthesizer = try KokoroSynthesizer(modelFile: modelFile, voicesFile: voicesFile)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(KokoroTTS.Constants.samplingRate),
                                         channels: 1) else {
            throw KokoroSpeechError.runtimeUnavailable
        }
        self.format = format

        audioEngine.attach(player)
        audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
    }

    // MARK: - SpeechSynthesizing

    func speak(_ chunks: [String], onFinish: @escaping () -> Void) {
        guard !chunks.isEmpty else { return onFinish() }
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
                guard let samples = try? await self.synthesizer.synthesize(chunk, voice: voice),
                      !samples.isEmpty else { continue }
                guard !Task.isCancelled else { return }
                self.schedule(samples)
            }
            guard let self, !Task.isCancelled else { return }
            self.allChunksScheduled = true
            // Everything may already have played if the reply was short.
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
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            UnsafeMutableRawPointer(channel)
                .copyMemory(from: UnsafeRawPointer(base),
                            byteCount: source.count * MemoryLayout<Float>.stride)
        }

        if !audioEngine.isRunning {
            do { try audioEngine.start() } catch { return }
        }

        pendingBuffers += 1
        // `.dataPlayedBack` fires when the audio has actually been heard, not
        // when it was consumed from the queue — the difference matters for
        // when the UI's stop button reverts to play.
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
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
