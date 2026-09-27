import SwiftUI

/// The painted backdrop for the Ocean theme: light falling through water.
///
/// Built on the same terms as `AlbumStarfield` — a graded wash, soft shapes, a
/// seeded field drawn once, and nothing that animates — so it can sit behind a
/// scrolling list for as long as the app is open without costing anything.
///
/// What makes it water rather than a blue sky is the direction. Light enters
/// from one edge and weakens with depth: the wash darkens downward, the shafts
/// all lean the same way and fade out before they reach the bottom, and the
/// drifting particles catch more light near the surface than in the deep.
struct AlbumOceanDepths: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.278, blue: 0.353),
                    Color(red: 0.027, green: 0.176, blue: 0.239),
                    Color(red: 0.012, green: 0.086, blue: 0.129)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                ZStack {
                    ForEach(Self.shafts.indices, id: \.self) { index in
                        shaft(Self.shafts[index], in: proxy.size)
                    }
                }
                .blur(radius: 22)
                .blendMode(.plusLighter)
            }

            Canvas { context, size in
                for mote in Self.motes {
                    let center = CGPoint(x: mote.x * size.width, y: mote.y * size.height)
                    let rect = CGRect(x: center.x - mote.radius, y: center.y - mote.radius,
                                      width: mote.radius * 2, height: mote.radius * 2)

                    if mote.isBubble {
                        // A ring, not a disc. A bubble is mostly the water
                        // behind it plus a bright edge, and a filled circle at
                        // this size reads as a speck of dirt instead.
                        context.stroke(Path(ellipseIn: rect),
                                       with: .color(.white.opacity(mote.opacity)),
                                       lineWidth: 0.8)
                        context.fill(Path(ellipseIn: rect),
                                     with: .color(.white.opacity(mote.opacity * 0.18)))
                    } else {
                        context.fill(Path(ellipseIn: rect),
                                     with: .color(.white.opacity(mote.opacity)))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// One shaft: a narrow band leaning off vertical, brightest where it enters
    /// and gone before the bottom of the screen.
    private func shaft(_ shaft: Shaft, in size: CGSize) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.75, green: 0.95, blue: 1.0).opacity(shaft.strength),
                        Color(red: 0.55, green: 0.85, blue: 0.95).opacity(shaft.strength * 0.35),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size.width * shaft.width, height: size.height * shaft.length)
            .rotationEffect(.degrees(shaft.angle), anchor: .top)
            .position(x: size.width * shaft.x, y: size.height * shaft.length / 2)
    }

    // MARK: - The field

    private struct Shaft {
        let x: Double
        let width: Double
        let length: Double
        let angle: Double
        let strength: Double
    }

    /// Placed by hand rather than generated. Five of them, and the eye reads an
    /// even spread as a pattern — the uneven spacing and the one wide shaft are
    /// what keep it from looking like a comb.
    private static let shafts: [Shaft] = [
        Shaft(x: 0.16, width: 0.10, length: 0.78, angle: 11, strength: 0.16),
        Shaft(x: 0.30, width: 0.05, length: 0.60, angle: 14, strength: 0.10),
        Shaft(x: 0.52, width: 0.16, length: 0.92, angle: 9,  strength: 0.20),
        Shaft(x: 0.72, width: 0.07, length: 0.68, angle: 13, strength: 0.12),
        Shaft(x: 0.88, width: 0.11, length: 0.84, angle: 10, strength: 0.14)
    ]

    private struct Mote {
        let x: Double
        let y: Double
        let radius: Double
        let opacity: Double
        let isBubble: Bool
    }

    private static let motes: [Mote] = generate(count: 130)

    private static func generate(count: Int) -> [Mote] {
        var rng = SeededGenerator(seed: 0x0CEA_11DE)
        return (0..<count).map { _ in
            let y = Double.random(in: 0...1, using: &rng)
            // Light falls off with depth, so a particle near the bottom is dim
            // whatever its size. Without this the field is evenly lit and the
            // gradient behind it stops reading as depth.
            let litByDepth = 1.0 - (y * 0.72)
            let isBubble = Double.random(in: 0...1, using: &rng) < 0.14
            return Mote(
                x: Double.random(in: 0...1, using: &rng),
                y: y,
                radius: isBubble
                    ? Double.random(in: 1.8...5.0, using: &rng)
                    : Double.random(in: 0.5...2.1, using: &rng),
                opacity: (isBubble ? 0.30 : 0.22) * litByDepth,
                isBubble: isBubble
            )
        }
    }
}
