import SwiftUI

/// The painted backdrop for the Sunrise theme: the few minutes before the sun
/// clears the horizon.
///
/// Dawn rather than daylight, which is what lets it stay dark. A risen sun
/// means a bright sky, white cards and black text, and the light-backdrop
/// problem that parked Blue Sky. Here the sun is still mostly below the line:
/// the ground is deep indigo, the warmth is all near the bottom, and text over
/// it reads the way it does on every other painted theme.
///
/// Same rules as the rest — a graded wash, soft blurred shapes, a seeded field
/// drawn once, nothing animating.
struct AlbumSunrise: View {
    /// How far up the screen the horizon sits. The sun breaks it from below.
    private static let horizon: Double = 0.78

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.047, blue: 0.129),
                    Color(red: 0.145, green: 0.086, blue: 0.204),
                    Color(red: 0.392, green: 0.165, blue: 0.239),
                    Color(red: 0.706, green: 0.322, blue: 0.239),
                    Color(red: 0.898, green: 0.518, blue: 0.263)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Canvas { context, size in
                // The last stars, only in the dark half and fading as the sky
                // warms. A sunrise with a full starfield is a night sky with
                // odd colours.
                for star in Self.stars {
                    let y = star.y * Self.horizon
                    let fade = 1.0 - (y / Self.horizon)
                    let opacity = star.opacity * fade
                    guard opacity > 0.02 else { continue }
                    let centre = CGPoint(x: star.x * size.width, y: y * size.height)
                    context.fill(
                        Path(ellipseIn: CGRect(x: centre.x - star.radius, y: centre.y - star.radius,
                                               width: star.radius * 2, height: star.radius * 2)),
                        with: .color(.white.opacity(opacity))
                    )
                }
            }

            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    sun(in: size)
                    clouds(in: size)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// A wide glow with a small disc inside it. The glow is most of the effect:
    /// a disc alone reads as a sticker, and at dawn the light in the sky is
    /// brighter than the sun's edge.
    private func sun(in size: CGSize) -> some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 1.0, green: 0.82, blue: 0.48).opacity(0.55),
                                 Color(red: 1.0, green: 0.55, blue: 0.30).opacity(0.18),
                                 .clear],
                        center: .center, startRadius: 0, endRadius: size.height * 0.30
                    )
                )
                .frame(width: size.width * 1.7, height: size.height * 0.62)
                .blur(radius: 30)

            Circle()
                .fill(Color(red: 1.0, green: 0.88, blue: 0.62))
                .frame(width: size.width * 0.34, height: size.width * 0.34)
                .blur(radius: 5)
        }
        // Centre placed below the horizon, so only its top shows.
        .position(x: size.width * 0.62, y: size.height * (Self.horizon + 0.10))
    }

    /// Thin bands lying across the sky, lit from beneath. Flatter and longer
    /// the lower they sit, which is what distance does to a cloud near the
    /// horizon.
    private func clouds(in size: CGSize) -> some View {
        ZStack {
            ForEach(Self.bands.indices, id: \.self) { index in
                let band = Self.bands[index]
                Capsule()
                    .fill(Color(red: 1.0, green: 0.72, blue: 0.52).opacity(band.opacity))
                    .frame(width: size.width * band.width, height: size.height * band.height)
                    .blur(radius: 9)
                    .position(x: size.width * band.x, y: size.height * band.y)
            }
        }
    }

    // MARK: - The field

    private struct Star {
        let x: Double
        let y: Double
        let radius: Double
        let opacity: Double
    }

    private struct Band {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let opacity: Double
    }

    /// Placed by hand. Five is few enough that a bad roll shows.
    private static let bands: [Band] = [
        Band(x: 0.30, y: 0.50, width: 0.52, height: 0.012, opacity: 0.30),
        Band(x: 0.68, y: 0.58, width: 0.40, height: 0.010, opacity: 0.24),
        Band(x: 0.40, y: 0.66, width: 0.70, height: 0.016, opacity: 0.34),
        Band(x: 0.74, y: 0.72, width: 0.46, height: 0.011, opacity: 0.26),
        Band(x: 0.22, y: 0.74, width: 0.38, height: 0.009, opacity: 0.20)
    ]

    private static let stars: [Star] = generate(count: 90)

    private static func generate(count: Int) -> [Star] {
        var rng = SeededGenerator(seed: 0x5C05_DA9E)
        return (0..<count).map { _ in
            let brightness = pow(Double.random(in: 0...1, using: &rng), 3)
            return Star(
                x: Double.random(in: 0...1, using: &rng),
                y: Double.random(in: 0...1, using: &rng),
                radius: 0.4 + brightness * 1.1,
                opacity: 0.20 + brightness * 0.55
            )
        }
    }
}
