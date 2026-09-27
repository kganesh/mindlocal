import Foundation

/// Deterministic pseudo-random values. The painted backdrops generate their
/// fields once at launch and must generate the *same* field every time, so the
/// sky or the water is a place rather than a re-roll.
///
/// xorshift64*: small, no dependencies, and good enough for placing dots.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9 : seed }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }
}
