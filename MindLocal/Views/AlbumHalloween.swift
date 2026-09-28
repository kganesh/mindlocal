import SwiftUI

/// The painted backdrop for the Halloween theme: a low orange moon, bare
/// branches reaching in from the edges, bats, and fog on the ground.
///
/// Restrained on purpose. This sits behind someone's journal for a month, and a
/// screen of cartoon pumpkins would be unusable by the third entry. The costume
/// is in the colour and the silhouettes; everything is still, and nothing
/// grins.
///
/// Same rules as the other painted backdrops: a graded wash, seeded shapes
/// generated once, nothing animating.
struct AlbumHalloween: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.031, blue: 0.086),
                    Color(red: 0.118, green: 0.063, blue: 0.145),
                    Color(red: 0.227, green: 0.110, blue: 0.129),
                    Color(red: 0.145, green: 0.086, blue: 0.075)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                moon(in: proxy.size)
                fog(in: proxy.size)
            }

            Canvas { context, size in
                for segment in Self.branches {
                    var path = Path()
                    path.move(to: CGPoint(x: segment.from.x * size.width,
                                          y: segment.from.y * size.height))
                    path.addLine(to: CGPoint(x: segment.to.x * size.width,
                                             y: segment.to.y * size.height))
                    context.stroke(path,
                                   with: .color(Color(red: 0.035, green: 0.020, blue: 0.043)),
                                   style: StrokeStyle(lineWidth: segment.width, lineCap: .round))
                }
                for bat in Self.bats { draw(bat, in: &context, size: size) }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Drawing

    /// Low and large, with a halo doing most of the work. A hard disc on a flat
    /// sky reads as a sticker; the glow is what puts it behind the branches.
    private func moon(in size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 1.0, green: 0.66, blue: 0.26).opacity(0.40),
                                 Color(red: 0.95, green: 0.45, blue: 0.18).opacity(0.12),
                                 .clear],
                        center: .center, startRadius: 0, endRadius: size.width * 0.52
                    )
                )
                .frame(width: size.width * 1.5, height: size.width * 1.5)

            Circle()
                .fill(Color(red: 0.98, green: 0.71, blue: 0.33))
                .frame(width: size.width * 0.42, height: size.width * 0.42)
                .overlay {
                    // Two shadows on the face. Not craters exactly; enough to
                    // stop it reading as a flat orange coin.
                    Circle()
                        .fill(Color(red: 0.86, green: 0.55, blue: 0.22).opacity(0.5))
                        .frame(width: size.width * 0.10, height: size.width * 0.09)
                        .offset(x: -size.width * 0.07, y: -size.width * 0.05)
                    Circle()
                        .fill(Color(red: 0.86, green: 0.55, blue: 0.22).opacity(0.4))
                        .frame(width: size.width * 0.07, height: size.width * 0.07)
                        .offset(x: size.width * 0.08, y: size.width * 0.06)
                }
                .blur(radius: 0.6)
        }
        .position(x: size.width * 0.70, y: size.height * 0.30)
    }

    /// One band, low and wide. Fog that reaches any higher hides the writing
    /// card rather than sitting under it.
    private func fog(in size: CGSize) -> some View {
        Capsule()
            .fill(Color(red: 0.55, green: 0.45, blue: 0.50).opacity(0.16))
            .frame(width: size.width * 1.6, height: size.height * 0.14)
            .blur(radius: 34)
            .position(x: size.width * 0.5, y: size.height * 0.94)
    }

    /// A bat is two wing curves and a body, small enough that the shape does
    /// all the work. Any more detail at this size turns to mud.
    private func draw(_ bat: Bat, in context: inout GraphicsContext, size: CGSize) {
        let centre = CGPoint(x: bat.x * size.width, y: bat.y * size.height)
        let span = bat.span
        var path = Path()
        path.move(to: CGPoint(x: centre.x - span, y: centre.y - span * 0.18))
        path.addQuadCurve(to: CGPoint(x: centre.x - span * 0.28, y: centre.y + span * 0.12),
                          control: CGPoint(x: centre.x - span * 0.62, y: centre.y + span * 0.40))
        path.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y - span * 0.16),
                          control: CGPoint(x: centre.x - span * 0.14, y: centre.y + span * 0.10))
        path.addQuadCurve(to: CGPoint(x: centre.x + span * 0.28, y: centre.y + span * 0.12),
                          control: CGPoint(x: centre.x + span * 0.14, y: centre.y + span * 0.10))
        path.addQuadCurve(to: CGPoint(x: centre.x + span, y: centre.y - span * 0.18),
                          control: CGPoint(x: centre.x + span * 0.62, y: centre.y + span * 0.40))
        path.addQuadCurve(to: CGPoint(x: centre.x - span, y: centre.y - span * 0.18),
                          control: CGPoint(x: centre.x, y: centre.y - span * 0.55))
        path.closeSubpath()
        context.fill(path, with: .color(Color(red: 0.043, green: 0.024, blue: 0.055)
            .opacity(bat.opacity)))
    }

    // MARK: - The field

    private struct Segment {
        let from: (x: Double, y: Double)
        let to: (x: Double, y: Double)
        let width: Double
    }

    private struct Bat {
        let x: Double
        let y: Double
        let span: Double
        let opacity: Double
    }

    /// Placed by hand. Three, spread apart and at different sizes so they read
    /// as being at different distances rather than as a flock in formation.
    private static let bats: [Bat] = [
        Bat(x: 0.22, y: 0.16, span: 11, opacity: 0.85),
        Bat(x: 0.38, y: 0.09, span: 7,  opacity: 0.65),
        Bat(x: 0.52, y: 0.21, span: 5,  opacity: 0.50)
    ]

    private static let branches: [Segment] = {
        var rng = SeededGenerator(seed: 0x8A11_0BEE)
        var segments: [Segment] = []

        /// Grows one branch and its forks. Each child is shorter, thinner and
        /// turned away from its parent, which is the whole of what makes a line
        /// look like a branch instead of a crack.
        func grow(from origin: (x: Double, y: Double),
                  angle: Double, length: Double, width: Double, depth: Int) {
            guard depth > 0, width > 0.35 else { return }
            let end = (x: origin.x + cos(angle) * length,
                       y: origin.y + sin(angle) * length * 0.55)
            segments.append(Segment(from: origin, to: end, width: width))

            let forks = depth > 2 ? 2 : Int.random(in: 1...2, using: &rng)
            for _ in 0..<forks {
                let turn = Double.random(in: 0.28...0.72, using: &rng)
                    * (Bool.random(using: &rng) ? 1 : -1)
                grow(from: end,
                     angle: angle + turn,
                     length: length * Double.random(in: 0.58...0.76, using: &rng),
                     width: width * 0.62,
                     depth: depth - 1)
            }
        }

        // Two limbs reaching in from the upper corners, leaving the middle of
        // the sky clear for the moon and the writing card below it.
        grow(from: (x: -0.02, y: 0.02), angle: 0.55, length: 0.30, width: 7, depth: 5)
        grow(from: (x: 1.02, y: -0.01), angle: 2.55, length: 0.26, width: 6, depth: 5)
        return segments
    }()
}
