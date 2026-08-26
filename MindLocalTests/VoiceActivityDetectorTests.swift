import XCTest
@testable import MindLocal

/// The gate that keeps Whisper from inventing text on silence.
///
/// These are the tests the existing suite can't give us: `MockSpeechService`
/// isolates the view models from transcription entirely, so nothing else here
/// exercises the one behaviour that decides whether Whisper is usable in an app
/// where users pause to think mid-sentence.
final class VoiceActivityDetectorTests: XCTestCase {

    private let vad = VoiceActivityDetector()
    private let sampleRate: Double = 16_000

    // MARK: - Signal generators
    //
    // Synthesised rather than recorded so the thresholds are asserted against
    // known amplitudes. Sine tones, not noise, so per-frame RMS is exactly
    // amplitude/√2 and the expected values can be reasoned about.

    private func tone(amplitude: Float, seconds: Double, frequency: Double = 220) -> [Float] {
        let count = Int(seconds * sampleRate)
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            amplitude * Float(sin(2 * .pi * frequency * Double(index) / sampleRate))
        }
    }

    private func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * sampleRate))
    }

    /// Bursts separated by gaps — the shape that distinguishes speech from
    /// steady noise at the same amplitude.
    private func bursts(amplitude: Float, count: Int,
                        burst: Double = 0.2, gap: Double = 0.1) -> [Float] {
        (0..<count).flatMap { _ in
            tone(amplitude: amplitude, seconds: burst) + silence(seconds: gap)
        }
    }

    // MARK: - The case that matters: silence must not reach the model

    func test_pureSilence_isNotSpeech() {
        XCTAssertFalse(vad.containsSpeech(silence(seconds: 3)))
    }

    func test_roomTone_belowFloor_isNotSpeech() {
        // ~0.0028 RMS, half the -45 dBFS floor.
        XCTAssertFalse(vad.containsSpeech(tone(amplitude: 0.004, seconds: 3)))
    }

    func test_steadyHum_aboveFloor_isNotSpeech() {
        // Clears the floor but never varies — a fan, not a voice. This is the
        // input that makes Whisper produce "Thank you for watching".
        let hum = tone(amplitude: 0.03, seconds: 3)
        XCTAssertGreaterThan(vad.frameEnergies(hum).max() ?? 0, vad.silenceFloor)
        XCTAssertFalse(vad.containsSpeech(hum))
    }

    func test_singleClick_isNotSpeech() {
        // One loud 20 ms frame: a mic bump, below the 200 ms minimum.
        let click = tone(amplitude: 0.3, seconds: 0.02) + silence(seconds: 2)
        XCTAssertFalse(vad.containsSpeech(click))
    }

    func test_emptyBuffer_isNotSpeech() {
        XCTAssertFalse(vad.containsSpeech([]))
    }

    func test_bufferShorterThanOneFrame_isNotSpeech() {
        XCTAssertFalse(vad.containsSpeech(tone(amplitude: 0.5, seconds: 0.01)))
    }

    // MARK: - Real speech must still get through

    func test_quietBurstySpeech_isSpeech() {
        // Between the floor and the confident level, so this passes only via
        // the variability test — the path that separates it from the hum above.
        XCTAssertTrue(vad.containsSpeech(bursts(amplitude: 0.03, count: 5)))
    }

    func test_quietSpeech_isSpeech_whenItOccupiesMostOfTheBuffer() {
        // Regression: an earlier peak-to-median test failed exactly here. At a
        // 67% speech duty cycle the median sits inside the speech, so the ratio
        // reads 1.0 — the same value steady hum produces. Coefficient of
        // variation is duty-cycle independent, which is why it replaced it.
        let mostlySpeech = bursts(amplitude: 0.03, count: 5, burst: 0.2, gap: 0.1)
        XCTAssertGreaterThan(
            VoiceActivityDetector.coefficientOfVariation(of: vad.frameEnergies(mostlySpeech)),
            vad.minEnergyVariation)
        XCTAssertTrue(vad.containsSpeech(mostlySpeech))
    }

    func test_coefficientOfVariation_isZeroForSteadySignal() {
        let steady = vad.frameEnergies(tone(amplitude: 0.03, seconds: 2))
        XCTAssertEqual(VoiceActivityDetector.coefficientOfVariation(of: steady), 0, accuracy: 0.02)
    }

    func test_coefficientOfVariation_isZeroForEmptyOrSilentInput() {
        XCTAssertEqual(VoiceActivityDetector.coefficientOfVariation(of: []), 0)
        XCTAssertEqual(VoiceActivityDetector.coefficientOfVariation(of: [0, 0, 0]), 0)
    }

    func test_loudContinuousSpeech_isSpeech() {
        // Flat, so burstiness would reject it; loud enough to skip that check.
        // Guards against rejecting someone speaking without pauses.
        XCTAssertTrue(vad.containsSpeech(tone(amplitude: 0.2, seconds: 2)))
    }

    func test_speechFollowedByLongPause_isStillSpeech() {
        // The MindLocal case: a sentence, then thinking time. The pause must
        // not erase the sentence that preceded it.
        let capture = bursts(amplitude: 0.08, count: 4) + silence(seconds: 5)
        XCTAssertTrue(vad.containsSpeech(capture))
    }

    // MARK: - RMS

    func test_rms_ofSilence_isZero() {
        XCTAssertEqual(vad.rms(silence(seconds: 0.1)[...]), 0, accuracy: 1e-6)
    }

    func test_rms_ofTone_isAmplitudeOverRootTwo() {
        let signal = tone(amplitude: 0.5, seconds: 0.1)
        XCTAssertEqual(vad.rms(signal[...]), 0.5 / Float(2).squareRoot(), accuracy: 0.01)
    }

    func test_frameEnergies_dropsTrailingPartialFrame() {
        // 10 whole frames plus 100 leftover samples; the partial frame would
        // have a misleading RMS, so it must not appear.
        let signal = tone(amplitude: 0.1, seconds: 0)
            + [Float](repeating: 0.1, count: VoiceActivityDetector.frameSamples * 10 + 100)
        XCTAssertEqual(vad.frameEnergies(signal).count, 10)
    }

    // MARK: - Window splitting

    func test_quietestBoundary_findsTheGap() {
        // 30 s of speech with a 400 ms pause starting at 27 s.
        let signal = tone(amplitude: 0.2, seconds: 27)
            + silence(seconds: 0.4)
            + tone(amplitude: 0.2, seconds: 2.6)

        let boundary = vad.quietestBoundary(in: signal,
                                            searchingLast: 4,
                                            sampleRate: sampleRate)
        let cut = try? XCTUnwrap(boundary)
        guard let cut else { return XCTFail("expected a boundary in the pause") }

        let seconds = Double(cut) / sampleRate
        XCTAssertGreaterThanOrEqual(seconds, 27.0)
        XCTAssertLessThanOrEqual(seconds, 27.4)
    }

    func test_quietestBoundary_isNilWhenTailIsUniformlyLoud() {
        // Nothing quiet to cut on — the caller must hard-cut rather than stall,
        // since Whisper's window is already full.
        XCTAssertNil(vad.quietestBoundary(in: tone(amplitude: 0.2, seconds: 30),
                                          searchingLast: 4,
                                          sampleRate: sampleRate))
    }

    func test_quietestBoundary_isNilForBufferShorterThanAFrame() {
        XCTAssertNil(vad.quietestBoundary(in: [0, 0, 0],
                                          searchingLast: 4,
                                          sampleRate: sampleRate))
    }

    // MARK: - Transcript assembly

    func test_join_insertsOneSpace() {
        XCTAssertEqual(WhisperSpeechService.join("I decided", "to take the offer"),
                       "I decided to take the offer")
    }

    func test_join_toleratesEmptyAndPaddedInput() {
        XCTAssertEqual(WhisperSpeechService.join("", "first words"), "first words")
        XCTAssertEqual(WhisperSpeechService.join("first words", ""), "first words")
        XCTAssertEqual(WhisperSpeechService.join("  a  ", "  b  "), "a b")
        XCTAssertEqual(WhisperSpeechService.join("", ""), "")
    }
}
