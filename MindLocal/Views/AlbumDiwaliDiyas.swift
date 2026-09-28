import SwiftUI

/// The painted backdrop for the Diwali theme: rows of diyas burning in the
/// dark, and the light they throw.
///
/// The lamps are small and near the bottom, which is the point. A diya lights a
/// doorstep, not a stadium, and the drawing has to earn its warmth from a lot
/// of dark rather than from filling the screen with orange. The glows are added
/// together, so the space between two lamps is brighter than either alone.
///
/// Same rules as the other painted backdrops: a graded wash, seeded embers
/// generated once, nothing animating. A still flame is a photograph of a flame.
struct AlbumDiwaliDiyas: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.047, green: 0.031, blue: 0.075),
                    Color(red: 0.098, green: 0.051, blue: 0.098),
                    Color(red: 0.169, green: 0.078, blue: 0.098),
                    Color(red: 0.125, green: 0.067, blue: 0.075)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Glow first and added together, so the lamps light each other's
            // surroundings instead of each sitting in its own circle.
            Canvas { context, size in
                context.blendMode = .plusLighter
                for row in Self.rows {
                    for lamp in Self.lamps(in: row) {
                        let flame = Self.flamePoint(lamp, in: row, size: size)
                        let radius = row.scale * size.width * 7.0
                        context.fill(
                            Path(ellipseIn: CGRect(x: flame.x - radius, y: flame.y - radius,
                                                   width: radius * 2, height: radius * 2)),
                            with: .radialGradient(
                                Gradient(colors: [
                                    Color(red: 1.0, green: 0.68, blue: 0.28).opacity(0.34 * row.brightness),
                                    Color(red: 0.95, green: 0.42, blue: 0.16).opacity(0.09 * row.brightness),
                                    .clear
                                ]),
                                center: flame, startRadius: 0, endRadius: radius
                            )
                        )
                    }
                }
            }
            .blur(radius: 8)

            Canvas { context, size in
                for row in Self.rows {
                    for lamp in Self.lamps(in: row) { draw(lamp, in: row, context: &context, size: size) }
                }
                // Embers last, so they rise through the light rather than
                // behind it.
                for ember in Self.embers {
                    let centre = CGPoint(x: ember.x * size.width, y: ember.y * size.height)
                    context.fill(
                        Path(ellipseIn: CGRect(x: centre.x - ember.radius, y: centre.y - ember.radius,
                                               width: ember.radius * 2, height: ember.radius * 2)),
                        with: .color(Color(red: 1.0, green: 0.78, blue: 0.42).opacity(ember.opacity))
                    )
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Drawing

    /// A diya is a shallow clay bowl with a pinched lip, and a flame standing
    /// above the lip rather than in the middle of the bowl. Getting the flame
    /// off-centre is most of what makes it read as an oil lamp.
    private func draw(_ lamp: Lamp, in row: Row, context: inout GraphicsContext, size: CGSize) {
        let unit = row.scale * size.width
        let base = CGPoint(x: lamp.x * size.width, y: row.y * size.height)

        var bowl = Path()
        bowl.move(to: CGPoint(x: base.x - unit, y: base.y))
        bowl.addQuadCurve(to: CGPoint(x: base.x + unit, y: base.y),
                          control: CGPoint(x: base.x, y: base.y + unit * 2.0))
        bowl.closeSubpath()
        context.fill(bowl, with: .color(Color(red: 0.42, green: 0.20, blue: 0.13)
            .opacity(row.brightness)))

        // The lit rim. Clay catches the flame along its near edge, and that
        // line is what separates the bowl from the dark behind it.
        var rim = Path()
        rim.move(to: CGPoint(x: base.x - unit, y: base.y))
        rim.addLine(to: CGPoint(x: base.x + unit, y: base.y))
        context.stroke(rim,
                       with: .color(Color(red: 0.85, green: 0.52, blue: 0.28)
                        .opacity(0.9 * row.brightness)),
                       style: StrokeStyle(lineWidth: max(0.8, unit * 0.22), lineCap: .round))

        let flame = Self.flamePoint(lamp, in: row, size: size)
        let height = unit * 1.9
        let width = unit * 0.62

        var body = Path()
        body.move(to: CGPoint(x: flame.x, y: flame.y - height))
        body.addQuadCurve(to: CGPoint(x: flame.x - width, y: flame.y),
                          control: CGPoint(x: flame.x - width * 0.95, y: flame.y - height * 0.42))
        body.addQuadCurve(to: CGPoint(x: flame.x + width, y: flame.y),
                          control: CGPoint(x: flame.x, y: flame.y + width * 0.85))
        body.addQuadCurve(to: CGPoint(x: flame.x, y: flame.y - height),
                          control: CGPoint(x: flame.x + width * 0.95, y: flame.y - height * 0.42))
        context.fill(body, with: .color(Color(red: 1.0, green: 0.71, blue: 0.24)
            .opacity(0.95 * row.brightness)))

        // The hot core, smaller and paler, sitting low in the flame where the
        // wick is.
        var core = Path()
        core.move(to: CGPoint(x: flame.x, y: flame.y - height * 0.58))
        core.addQuadCurve(to: CGPoint(x: flame.x - width * 0.40, y: flame.y - height * 0.06),
                          control: CGPoint(x: flame.x - width * 0.42, y: flame.y - height * 0.30))
        core.addQuadCurve(to: CGPoint(x: flame.x + width * 0.40, y: flame.y - height * 0.06),
                          control: CGPoint(x: flame.x, y: flame.y + height * 0.10))
        core.addQuadCurve(to: CGPoint(x: flame.x, y: flame.y - height * 0.58),
                          control: CGPoint(x: flame.x + width * 0.42, y: flame.y - height * 0.30))
        context.fill(core, with: .color(Color(red: 1.0, green: 0.95, blue: 0.78)
            .opacity(0.85 * row.brightness)))
    }

    private static func flamePoint(_ lamp: Lamp, in row: Row, size: CGSize) -> CGPoint {
        let unit = row.scale * size.width
        return CGPoint(x: lamp.x * size.width + unit * lamp.lip, y: row.y * size.height - unit * 0.1)
    }

    // MARK: - The field

    private struct Row {
        /// Where the lamps stand, as a fraction of screen height.
        let y: Double
        let count: Int
        /// Bowl half-width as a fraction of screen width.
        let scale: Double
        /// Dimmer reads as further back, the same trick the rest of the family
        /// uses for depth.
        let brightness: Double
        let inset: Double
        let seed: UInt64
    }

    private struct Lamp {
        let x: Double
        /// Which side of the bowl the wick rests on, so a row of lamps is not a
        /// row of identical stamps.
        let lip: Double
    }

    /// Two rows. The far one higher, smaller, dimmer and more numerous.
    private static let rows: [Row] = [
        Row(y: 0.82, count: 9, scale: 0.016, brightness: 0.55, inset: 0.06, seed: 0xD1_9A01),
        Row(y: 0.93, count: 5, scale: 0.030, brightness: 1.00, inset: 0.12, seed: 0xD1_9A02)
    ]

    private static func lamps(in row: Row) -> [Lamp] {
        var rng = SeededGenerator(seed: row.seed)
        let span = 1.0 - row.inset * 2
        return (0..<row.count).map { index in
            let t = row.count == 1 ? 0.5 : Double(index) / Double(row.count - 1)
            let jitter = Double.random(in: -0.012...0.012, using: &rng)
            return Lamp(x: row.inset + span * t + jitter,
                        lip: Double.random(in: -0.55...0.55, using: &rng))
        }
    }

    private struct Ember {
        let x: Double
        let y: Double
        let radius: Double
        let opacity: Double
    }

    /// Rising from the lamps and fading out well before the top. Embers that
    /// reach the ceiling read as stars, and this is not a night sky.
    private static let embers: [Ember] = {
        var rng = SeededGenerator(seed: 0xD1_9AE3)
        return (0..<64).map { _ in
            let height = pow(Double.random(in: 0...1, using: &rng), 1.7)
            let y = 0.92 - height * 0.62
            return Ember(
                x: Double.random(in: 0.05...0.95, using: &rng),
                y: y,
                radius: Double.random(in: 0.6...1.8, using: &rng),
                opacity: (1.0 - height) * Double.random(in: 0.30...0.75, using: &rng)
            )
        }
    }()
}
