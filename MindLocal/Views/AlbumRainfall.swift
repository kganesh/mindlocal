import SwiftUI

/// The painted backdrop for the Rain theme: light rain against an overcast
/// night, with one warm lamp somewhere off screen.
///
/// Same rules as the other painted backdrops — seeded once, drawn once, nothing
/// animating. Rain is the one subject here where that is a real constraint
/// rather than a saving: falling rain is motion, and a still frame of it is all
/// this can be. What carries it instead is depth. Three layers of streaks sit
/// at different distances, and the far ones are shorter, thinner, fainter and
/// more numerous, which is what a photograph of rain looks like when the
/// shutter is open long enough to hold the near drops still.
struct AlbumRainfall: View {
    /// Rain falls with the wind, not straight down, and every streak leans the
    /// same way. Varying the angle per streak reads as snow.
    private static let leanDegrees: Double = 13

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.043, green: 0.063, blue: 0.078),
                    Color(red: 0.063, green: 0.086, blue: 0.102),
                    Color(red: 0.086, green: 0.106, blue: 0.118)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    // A lamp off the bottom-left edge. It gives the rain
                    // something to be lit by, and it is where the warm date
                    // colour in this palette comes from.
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 1.0, green: 0.80, blue: 0.55).opacity(0.16), .clear],
                                center: .center, startRadius: 0, endRadius: size.height * 0.30
                            )
                        )
                        .frame(width: size.width * 1.1, height: size.height * 0.55)
                        .position(x: size.width * 0.12, y: size.height * 0.92)
                        .blur(radius: 50)

                    // Low cloud, pale and wide, sitting over the top third.
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.62, green: 0.70, blue: 0.76).opacity(0.14), .clear],
                                center: .center, startRadius: 0, endRadius: size.height * 0.26
                            )
                        )
                        .frame(width: size.width * 1.8, height: size.height * 0.42)
                        .position(x: size.width * 0.62, y: size.height * 0.14)
                        .blur(radius: 46)
                }
                .blendMode(.plusLighter)
            }

            Canvas { context, size in
                let radians = Self.leanDegrees * .pi / 180
                let lean = (x: sin(radians), y: cos(radians))

                for streak in Self.streaks {
                    let start = CGPoint(x: streak.x * size.width, y: streak.y * size.height)
                    let end = CGPoint(x: start.x + lean.x * streak.length,
                                      y: start.y + lean.y * streak.length)

                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)

                    // Faded at both ends. A streak with hard ends reads as a
                    // scratch on the screen; rain has no start and no stop
                    // inside the frame.
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [
                                .clear,
                                Color(red: 0.85, green: 0.92, blue: 0.96).opacity(streak.opacity),
                                .clear
                            ]),
                            startPoint: start, endPoint: end
                        ),
                        lineWidth: streak.width
                    )
                }

                // A handful of drops close enough to be out of focus.
                for drop in Self.drops {
                    let center = CGPoint(x: drop.x * size.width, y: drop.y * size.height)
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - drop.radius, y: center.y - drop.radius * 1.6,
                                               width: drop.radius * 2, height: drop.radius * 3.2)),
                        with: .color(.white.opacity(drop.opacity))
                    )
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - The field

    private struct Streak {
        let x: Double
        let y: Double
        let length: Double
        let width: Double
        let opacity: Double
    }

    private struct Drop {
        let x: Double
        let y: Double
        let radius: Double
        let opacity: Double
    }

    private static let streaks: [Streak] = generateStreaks()
    private static let drops: [Drop] = generateDrops(count: 14)

    /// Three distances, far to near. Counts fall and everything else grows, so
    /// the near layer reads as near even though nothing moves.
    private static func generateStreaks() -> [Streak] {
        var rng = SeededGenerator(seed: 0x4A1F_D20D)
        let layers: [(count: Int, length: ClosedRange<Double>, width: Double, opacity: ClosedRange<Double>)] = [
            (70, 9...18,  0.6, 0.05...0.11),
            (42, 18...34, 0.9, 0.09...0.18),
            (18, 34...58, 1.3, 0.14...0.26)
        ]

        return layers.flatMap { layer in
            (0..<layer.count).map { _ in
                Streak(
                    x: Double.random(in: -0.05...1.0, using: &rng),
                    y: Double.random(in: -0.05...1.0, using: &rng),
                    length: Double.random(in: layer.length, using: &rng),
                    width: layer.width,
                    opacity: Double.random(in: layer.opacity, using: &rng)
                )
            }
        }
    }

    private static func generateDrops(count: Int) -> [Drop] {
        var rng = SeededGenerator(seed: 0x0D_20B5)
        return (0..<count).map { _ in
            Drop(
                x: Double.random(in: 0...1, using: &rng),
                y: Double.random(in: 0...1, using: &rng),
                radius: Double.random(in: 1.0...2.2, using: &rng),
                opacity: Double.random(in: 0.06...0.14, using: &rng)
            )
        }
    }
}
