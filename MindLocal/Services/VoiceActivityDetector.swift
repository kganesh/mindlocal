import Foundation

/// Energy-based voice activity detection over 16 kHz mono float audio.
///
/// Exists because Whisper hallucinates on silence: fed room tone it emits
/// confident filler ("Thank you for watching", repeated phrases) rather than
/// nothing. MindLocal's users pause mid-sentence to think, so near-silent
/// windows are the normal case, not the edge case — every buffer goes through
/// `containsSpeech` before it reaches the model.
///
/// Deliberately not a learned VAD: this runs on every refresh pass alongside
/// Whisper inference, and a percentile over frame energies costs microseconds.
/// The thresholds below are tuned for iPhone mic input with AGC engaged.
struct VoiceActivityDetector {

    /// Frame size for energy analysis: 20 ms at 16 kHz.
    ///
    /// Short enough to sit inside the gaps between words (so those gaps pull
    /// the median down and make speech look bursty), long enough that a single
    /// transient doesn't read as a whole frame of speech.
    static let frameSamples = 320

    /// RMS below this reads as silence regardless of anything else.
    ///
    /// -45 dBFS. Room tone on an iPhone mic sits near -55 dBFS; conversational
    /// speech at arm's length lands between -30 and -10 dBFS. The gap is wide,
    /// so this only has to be roughly right.
    var silenceFloor: Float = 0.0056

    /// RMS above which a frame is speech on its own, skipping the burstiness
    /// test. Guards against rejecting genuinely continuous loud speech.
    var confidentSpeechLevel: Float = 0.05

    /// Minimum coefficient of variation (std ÷ mean) of frame energies for
    /// marginal audio to count as speech.
    ///
    /// Speech energy swings at the syllable rate, so its frame energies spread
    /// widely around their mean; steady noise (fans, road noise, hum) sits near
    /// zero variation even when it clears `silenceFloor`, which is exactly the
    /// input that makes Whisper invent text.
    ///
    /// Peak-to-median was the obvious choice here and is wrong: once speech
    /// occupies more than half the buffer the median lands *inside* the speech
    /// and the ratio collapses to 1.0, indistinguishable from hum. Coefficient
    /// of variation doesn't care about duty cycle.
    var minEnergyVariation: Float = 0.25

    /// Speech has to persist this long to count, in frames (10 × 20 ms).
    /// Rejects door clicks and mic bumps.
    var minSpeechFrames = 10

    // MARK: - Analysis

    /// Root-mean-square amplitude of one frame.
    func rms(_ frame: ArraySlice<Float>) -> Float {
        guard !frame.isEmpty else { return 0 }
        let sumOfSquares = frame.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumOfSquares / Float(frame.count)).squareRoot()
    }

    /// Per-frame RMS across the buffer. A trailing partial frame is dropped —
    /// its RMS would be computed over fewer samples and skew the percentiles.
    func frameEnergies(_ samples: [Float]) -> [Float] {
        let frameCount = samples.count / Self.frameSamples
        guard frameCount > 0 else { return [] }
        return (0..<frameCount).map { index in
            let start = index * Self.frameSamples
            return rms(samples[start ..< start + Self.frameSamples])
        }
    }

    /// Whether this buffer is worth sending to Whisper.
    ///
    /// Three gates, cheapest first: nothing clears the noise floor; too little
    /// of it to be a word; or it clears the floor but is too flat to be speech.
    func containsSpeech(_ samples: [Float]) -> Bool {
        let energies = frameEnergies(samples)
        guard !energies.isEmpty else { return false }

        let peak = energies.max() ?? 0
        guard peak >= silenceFloor else { return false }

        let speechFrames = energies.filter { $0 >= silenceFloor }.count
        guard speechFrames >= minSpeechFrames else { return false }

        // Loud enough that variability doesn't need checking — guards against
        // rejecting someone speaking continuously without pauses.
        if peak >= confidentSpeechLevel { return true }

        return Self.coefficientOfVariation(of: energies) >= minEnergyVariation
    }

    /// Sample index of the quietest point within the last `window` seconds,
    /// for splitting a full 30 s buffer without cutting mid-syllable.
    ///
    /// Returns nil when the tail is uniformly loud — the caller should hard-cut
    /// rather than wait, since Whisper cannot take more than its window.
    func quietestBoundary(in samples: [Float],
                          searchingLast window: TimeInterval,
                          sampleRate: Double = 16_000) -> Int? {
        let searchSamples = min(samples.count, Int(window * sampleRate))
        guard searchSamples >= Self.frameSamples else { return nil }

        let searchStart = samples.count - searchSamples
        let tail = Array(samples[searchStart...])
        let energies = frameEnergies(tail)
        guard !energies.isEmpty else { return nil }

        guard let quietestIndex = energies.indices.min(by: { energies[$0] < energies[$1] }),
              energies[quietestIndex] < silenceFloor
        else { return nil }

        // Cut at the frame's midpoint so neither side clips a syllable onset.
        let offset = quietestIndex * Self.frameSamples + Self.frameSamples / 2
        return searchStart + offset
    }

    // MARK: - Helpers

    /// Spread of frame energies relative to their mean. Zero for a perfectly
    /// steady signal, large for anything that starts and stops.
    static func coefficientOfVariation(of values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Float(values.count)
        guard mean > 0 else { return 0 }
        let variance = values.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(values.count)
        return variance.squareRoot() / mean
    }
}
