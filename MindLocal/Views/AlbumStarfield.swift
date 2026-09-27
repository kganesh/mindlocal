import SwiftUI

/// The painted backdrop for the Night Sky theme: a graded sky, a faint band of
/// distant light, and a fixed field of stars.
///
/// The star positions are generated once into a static array from a seeded
/// generator, not drawn from `Double.random` inside the canvas. SwiftUI redraws
/// a background whenever anything above it changes — every keystroke, every
/// scroll that resizes a row — and a field that re-rolls on each pass reads as
/// static noise rather than a sky.
///
/// Nothing animates. A twinkle means redrawing a few hundred shapes behind
/// whatever the user is reading or typing, for the whole time the app is open,
/// and the fixed field is what lets this sit behind a scrolling list without
/// competing with it.
struct AlbumStarfield: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.024, green: 0.035, blue: 0.086),
                    Color(red: 0.043, green: 0.063, blue: 0.145),
                    Color(red: 0.071, green: 0.102, blue: 0.200)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // The suggestion of a galactic band, running corner to corner. Too
            // faint to identify, which is the point: it keeps the field from
            // reading as evenly scattered dots on a flat wash.
            GeometryReader { proxy in
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.055), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: proxy.size.height * 0.42
                        )
                    )
                    .frame(width: proxy.size.width * 1.7, height: proxy.size.height * 0.75)
                    .rotationEffect(.degrees(-28))
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.38)
                    .blur(radius: 26)
            }

            Canvas { context, size in
                for star in Self.stars {
                    let center = CGPoint(x: star.x * size.width, y: star.y * size.height)

                    // A halo under the brightest handful. Real bright stars
                    // bloom; without it the big ones look like pasted circles.
                    if star.radius > 1.5 {
                        let glow = star.radius * 4
                        context.fill(
                            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow,
                                                   width: glow * 2, height: glow * 2)),
                            with: .radialGradient(
                                Gradient(colors: [Color.white.opacity(0.16), .clear]),
                                center: center, startRadius: 0, endRadius: glow
                            )
                        )
                    }

                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - star.radius, y: center.y - star.radius,
                                               width: star.radius * 2, height: star.radius * 2)),
                        with: .color(star.tint.opacity(star.opacity))
                    )
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - The field

    private struct Star {
        let x: Double
        let y: Double
        let radius: Double
        let opacity: Double
        let tint: Color
    }

    private static let stars: [Star] = generate(count: 210)

    /// Stars are not white. Scattering a few warm and cool ones through an
    /// otherwise white field is most of what separates a night sky from
    /// speckle, and it costs nothing to draw.
    private static let tints: [Color] = [
        .white, .white, .white,
        Color(red: 0.86, green: 0.90, blue: 1.0),
        Color(red: 1.0, green: 0.94, blue: 0.85)
    ]

    private static func generate(count: Int) -> [Star] {
        var rng = SeededGenerator(seed: 0x5EED_5C47)
        return (0..<count).map { _ in
            // Most stars are faint. Cubing a uniform value pushes the
            // distribution down so the bright ones stay rare enough to read as
            // bright, rather than the field averaging out to a grey haze.
            let brightness = pow(Double.random(in: 0...1, using: &rng), 3)
            return Star(
                x: Double.random(in: 0...1, using: &rng),
                y: Double.random(in: 0...1, using: &rng),
                radius: 0.45 + brightness * 1.5,
                opacity: 0.22 + brightness * 0.7,
                tint: tints[Int.random(in: 0..<tints.count, using: &rng)]
            )
        }
    }
}
