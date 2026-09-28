import SwiftUI

/// The painted backdrop for the Rain on Glass theme: a window on a wet night,
/// lights blurred behind it, droplets beaded on the pane.
///
/// The difference from `AlbumRainfall` is where you are standing. That one is
/// out in the rain, watching it fall. This one is inside, and the rain is on
/// the glass between you and everything else. Both are still, but stillness
/// means something here: drops on a window genuinely do sit there.
///
/// What sells it is the focus split. The lights behind are heavily blurred
/// circles, because a camera focused on the pane cannot hold them; the drops
/// are sharp, with a rim and a highlight, because they are what the eye is on.
/// Blur everything and it is fog. Sharpen everything and it is confetti.
struct AlbumRainOnGlass: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.055, blue: 0.098),
                    Color(red: 0.063, green: 0.090, blue: 0.145),
                    Color(red: 0.086, green: 0.118, blue: 0.161)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { proxy in
                ZStack {
                    ForEach(Self.lights.indices, id: \.self) { index in
                        let light = Self.lights[index]
                        Circle()
                            .fill(light.color.opacity(light.opacity))
                            .frame(width: proxy.size.width * light.size,
                                   height: proxy.size.width * light.size)
                            .blur(radius: proxy.size.width * light.size * 0.32)
                            .position(x: proxy.size.width * light.x,
                                      y: proxy.size.height * light.y)
                    }
                }
                .blendMode(.plusLighter)
            }

            Canvas { context, size in
                for trail in Self.trails { draw(trail, in: &context, size: size) }
                for drop in Self.drops { draw(drop, in: &context, size: size) }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Drawing

    /// A drop is three marks: a pale body, a dark rim under it, and a small
    /// highlight up and left. The rim is what makes it sit on the glass rather
    /// than float in front of it.
    private func draw(_ drop: Drop, in context: inout GraphicsContext, size: CGSize) {
        let centre = CGPoint(x: drop.x * size.width, y: drop.y * size.height)
        let width = drop.radius * 2
        let height = drop.radius * 2 * drop.stretch
        let rect = CGRect(x: centre.x - width / 2, y: centre.y - height / 2,
                          width: width, height: height)

        context.fill(Path(ellipseIn: rect),
                     with: .color(.white.opacity(drop.opacity * 0.16)))
        context.stroke(Path(ellipseIn: rect),
                       with: .color(.black.opacity(drop.opacity * 0.22)),
                       lineWidth: max(0.5, drop.radius * 0.18))

        let glint = drop.radius * 0.34
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - drop.radius * 0.38 - glint / 2,
                                   y: centre.y - height * 0.22 - glint / 2,
                                   width: glint, height: glint)),
            with: .color(.white.opacity(drop.opacity * 0.55))
        )
    }

    /// A drop that has begun to run, leaving a thin wet line behind it. Only a
    /// few: a window where every drop has run is a window in a downpour, and
    /// this one is quieter than that.
    private func draw(_ trail: Trail, in context: inout GraphicsContext, size: CGSize) {
        let x = trail.x * size.width
        let top = trail.y * size.height
        let bottom = top + trail.length * size.height
        var path = Path()
        path.move(to: CGPoint(x: x, y: top))
        path.addLine(to: CGPoint(x: x, y: bottom))
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [.clear, .white.opacity(0.10), .white.opacity(0.04)]),
                startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: bottom)
            ),
            lineWidth: trail.width
        )
    }

    // MARK: - The field

    private struct Drop {
        let x: Double
        let y: Double
        let radius: Double
        /// Taller than wide, a little. Gravity pulls a bead out of round.
        let stretch: Double
        let opacity: Double
    }

    private struct Trail {
        let x: Double
        let y: Double
        let length: Double
        let width: Double
    }

    private struct Light {
        let x: Double
        let y: Double
        let size: Double
        let opacity: Double
        let color: Color
    }

    /// Out-of-focus lights, placed by hand. Warm and cool mixed, because a
    /// street at night is sodium and neon and a lit window, not one colour.
    private static let lights: [Light] = [
        Light(x: 0.18, y: 0.18, size: 0.30, opacity: 0.30, color: Color(red: 1.0, green: 0.72, blue: 0.38)),
        Light(x: 0.74, y: 0.12, size: 0.22, opacity: 0.22, color: Color(red: 0.45, green: 0.75, blue: 1.0)),
        Light(x: 0.62, y: 0.38, size: 0.36, opacity: 0.20, color: Color(red: 0.95, green: 0.45, blue: 0.55)),
        Light(x: 0.26, y: 0.52, size: 0.26, opacity: 0.18, color: Color(red: 0.50, green: 0.90, blue: 0.85)),
        Light(x: 0.86, y: 0.62, size: 0.30, opacity: 0.24, color: Color(red: 1.0, green: 0.78, blue: 0.45)),
        Light(x: 0.40, y: 0.80, size: 0.24, opacity: 0.16, color: Color(red: 0.62, green: 0.60, blue: 1.0)),
        Light(x: 0.08, y: 0.86, size: 0.20, opacity: 0.18, color: Color(red: 1.0, green: 0.60, blue: 0.40))
    ]

    private static let drops: [Drop] = generateDrops()
    private static let trails: [Trail] = generateTrails(count: 9)

    /// Three sizes, most of them small. A pane covered in evenly sized beads
    /// reads as a pattern; real glass has a lot of fine spray and a few fat
    /// drops that have gathered it.
    private static func generateDrops() -> [Drop] {
        var rng = SeededGenerator(seed: 0x61A5_5D0B)
        let layers: [(count: Int, radius: ClosedRange<Double>, opacity: ClosedRange<Double>)] = [
            (150, 0.8...2.0, 0.35...0.65),
            (48,  2.2...4.4, 0.55...0.85),
            (14,  4.8...8.5, 0.70...1.00)
        ]
        return layers.flatMap { layer in
            (0..<layer.count).map { _ in
                Drop(
                    x: Double.random(in: 0...1, using: &rng),
                    y: Double.random(in: 0...1, using: &rng),
                    radius: Double.random(in: layer.radius, using: &rng),
                    stretch: Double.random(in: 1.0...1.25, using: &rng),
                    opacity: Double.random(in: layer.opacity, using: &rng)
                )
            }
        }
    }

    private static func generateTrails(count: Int) -> [Trail] {
        var rng = SeededGenerator(seed: 0x7A41_1C0D)
        return (0..<count).map { _ in
            Trail(
                x: Double.random(in: 0.05...0.95, using: &rng),
                y: Double.random(in: 0.0...0.55, using: &rng),
                length: Double.random(in: 0.10...0.34, using: &rng),
                width: Double.random(in: 1.2...3.0, using: &rng)
            )
        }
    }
}
