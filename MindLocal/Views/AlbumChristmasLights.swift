import SwiftUI

/// The painted backdrop for the Christmas Lights theme: two strings of bulbs
/// hung across a winter night, with snow behind them.
///
/// The glow is the whole thing. A row of coloured dots is a row of coloured
/// dots; what makes it a string of lights is the halo around each one and the
/// fact that the halos overlap. So the bulbs are drawn small and the glows
/// large, added together rather than laid over one another, which is how light
/// behaves and paint does not.
///
/// Same rules as the other painted backdrops: a graded wash, seeded snow
/// generated once, nothing animating.
struct AlbumChristmasLights: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.027, green: 0.055, blue: 0.067),
                    Color(red: 0.047, green: 0.090, blue: 0.098),
                    Color(red: 0.035, green: 0.067, blue: 0.075),
                    Color(red: 0.020, green: 0.039, blue: 0.047)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Canvas { context, size in
                for flake in Self.snow {
                    let centre = CGPoint(x: flake.x * size.width, y: flake.y * size.height)
                    context.fill(
                        Path(ellipseIn: CGRect(x: centre.x - flake.radius, y: centre.y - flake.radius,
                                               width: flake.radius * 2, height: flake.radius * 2)),
                        with: .color(.white.opacity(flake.opacity))
                    )
                }
            }

            // Glows first and added together, so where two bulbs are close the
            // light between them is brighter than either alone.
            GeometryReader { proxy in
                Canvas { context, size in
                    context.blendMode = .plusLighter
                    for string in Self.strings {
                        for bulb in Self.bulbs(on: string) {
                            let centre = Self.position(of: bulb, on: string, in: size)
                            let radius = string.bulbSize * size.width * 5.5
                            context.fill(
                                Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                       width: radius * 2, height: radius * 2)),
                                with: .radialGradient(
                                    Gradient(colors: [bulb.color.opacity(0.42 * string.brightness),
                                                      bulb.color.opacity(0.10 * string.brightness),
                                                      .clear]),
                                    center: centre, startRadius: 0, endRadius: radius
                                )
                            )
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .blur(radius: 6)
            }

            Canvas { context, size in
                for string in Self.strings { draw(string, in: &context, size: size) }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Drawing

    /// The wire, then its bulbs. The wire sags, because a straight one reads as
    /// a shelf with lights on it.
    private func draw(_ string: LightString, in context: inout GraphicsContext, size: CGSize) {
        var wire = Path()
        let steps = 48
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let point = Self.wirePoint(t, on: string, in: size)
            if step == 0 { wire.move(to: point) } else { wire.addLine(to: point) }
        }
        context.stroke(wire,
                       with: .color(.black.opacity(0.55 * string.brightness)),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

        for bulb in Self.bulbs(on: string) {
            let hang = Self.wirePoint(bulb.t, on: string, in: size)
            let centre = Self.position(of: bulb, on: string, in: size)
            let radius = string.bulbSize * size.width

            var stem = Path()
            stem.move(to: hang)
            stem.addLine(to: CGPoint(x: centre.x, y: centre.y - radius))
            context.stroke(stem, with: .color(.black.opacity(0.6 * string.brightness)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

            // Taller than wide, the shape of a bulb rather than a bead.
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius * 1.25,
                                       width: radius * 2, height: radius * 2.5)),
                with: .color(bulb.color.opacity(0.92 * string.brightness))
            )
            // The filament, off-centre. It is what stops the bulb reading as a
            // flat coloured pill.
            let spark = radius * 0.42
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - spark / 2 - radius * 0.18,
                                       y: centre.y - spark / 2 - radius * 0.20,
                                       width: spark, height: spark)),
                with: .color(.white.opacity(0.75 * string.brightness))
            )
        }
    }

    // MARK: - Geometry

    /// A parabola, deepest in the middle. Close enough to the curve a hanging
    /// wire actually makes, and it needs no hyperbolic cosine to compute.
    private static func wirePoint(_ t: Double, on string: LightString, in size: CGSize) -> CGPoint {
        let y = string.startY + (string.endY - string.startY) * t + string.sag * 4 * t * (1 - t)
        return CGPoint(x: t * size.width, y: y * size.height)
    }

    private static func position(of bulb: Bulb, on string: LightString, in size: CGSize) -> CGPoint {
        let hang = wirePoint(bulb.t, on: string, in: size)
        return CGPoint(x: hang.x, y: hang.y + string.bulbSize * size.width * 2.1)
    }

    private static func bulbs(on string: LightString) -> [Bulb] {
        (0..<string.count).map { index in
            let t = (Double(index) + 0.5) / Double(string.count)
            return Bulb(t: t, color: palette[(index + string.colorOffset) % palette.count])
        }
    }

    // MARK: - The field

    private struct LightString {
        let startY: Double
        let endY: Double
        let sag: Double
        let count: Int
        let bulbSize: Double
        /// Dimmer reads as further away, the same trick the other backdrops use.
        let brightness: Double
        let colorOffset: Int
    }

    private struct Bulb {
        let t: Double
        let color: Color
    }

    /// The old five. Warm rather than saturated, so they sit in a night rather
    /// than glowing off the screen like a test pattern.
    private static let palette: [Color] = [
        Color(red: 0.91, green: 0.29, blue: 0.27),
        Color(red: 0.36, green: 0.72, blue: 0.40),
        Color(red: 0.95, green: 0.75, blue: 0.30),
        Color(red: 0.36, green: 0.58, blue: 0.88),
        Color(red: 0.90, green: 0.52, blue: 0.75)
    ]

    /// Two, the far one higher, dimmer and finer. One string alone looks like
    /// decoration; two at different depths looks like a place.
    private static let strings: [LightString] = [
        LightString(startY: 0.15, endY: 0.10, sag: 0.05, count: 11,
                    bulbSize: 0.0075, brightness: 0.55, colorOffset: 2),
        LightString(startY: 0.04, endY: 0.09, sag: 0.09, count: 8,
                    bulbSize: 0.0130, brightness: 1.00, colorOffset: 0)
    ]

    private struct Flake {
        let x: Double
        let y: Double
        let radius: Double
        let opacity: Double
    }

    private static let snow: [Flake] = {
        var rng = SeededGenerator(seed: 0xC417_5A05)
        return (0..<110).map { _ in
            let brightness = pow(Double.random(in: 0...1, using: &rng), 2)
            return Flake(
                x: Double.random(in: 0...1, using: &rng),
                y: Double.random(in: 0...1, using: &rng),
                radius: 0.5 + brightness * 1.5,
                opacity: 0.12 + brightness * 0.35
            )
        }
    }()
}
