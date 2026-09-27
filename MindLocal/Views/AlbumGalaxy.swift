import SwiftUI

/// The painted backdrop for the Galaxy theme.
///
/// Same construction as `AlbumStarfield` and `AlbumOceanDepths`: a graded wash,
/// soft blurred shapes, a seeded field drawn once, nothing animating.
///
/// What separates this from the plain night sky is structure. A starfield is
/// scattered evenly; a galaxy has a core, an axis, and a dust lane cutting
/// across it. Two thirds of the stars here are pulled toward that axis with a
/// cubed offset, so density falls away from the band the way it does in a
/// photograph, and the remaining third stays scattered as foreground.
struct AlbumGalaxy: View {
    /// Where the band runs. Everything else is positioned relative to these.
    private static let core = UnitPoint(x: 0.52, y: 0.40)
    private static let axisDegrees: Double = -24

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.031, green: 0.024, blue: 0.067),
                    Color(red: 0.055, green: 0.039, blue: 0.098),
                    Color(red: 0.020, green: 0.016, blue: 0.047)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    // Colour first, structure over it. The clouds are wide and
                    // faint; anything stronger stops reading as gas and starts
                    // reading as a gradient someone chose.
                    cloud(Color(red: 0.42, green: 0.22, blue: 0.75), at: UnitPoint(x: 0.30, y: 0.28),
                          scale: 1.15, opacity: 0.30, in: size)
                    cloud(Color(red: 0.85, green: 0.30, blue: 0.55), at: UnitPoint(x: 0.68, y: 0.52),
                          scale: 0.85, opacity: 0.22, in: size)
                    cloud(Color(red: 0.20, green: 0.55, blue: 0.85), at: UnitPoint(x: 0.44, y: 0.74),
                          scale: 0.95, opacity: 0.20, in: size)

                    galacticBand(in: size)
                    coreGlow(in: size)
                    // Last, so the lane cuts across the core rather than
                    // sitting behind it.
                    dustLane(in: size)
                }
                // destinationOut only removes what is already in its own
                // layer, so the structure has to be composited as one before
                // the lane can cut anything out of it.
                .compositingGroup()
                .blendMode(.plusLighter)
            }

            Canvas { context, size in
                for star in Self.stars {
                    let center = CGPoint(x: star.x * size.width, y: star.y * size.height)

                    if star.radius > 1.4 {
                        let glow = star.radius * 4.5
                        context.fill(
                            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow,
                                                   width: glow * 2, height: glow * 2)),
                            with: .radialGradient(
                                Gradient(colors: [star.tint.opacity(0.20), .clear]),
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

    // MARK: - Structure

    private func cloud(_ color: Color, at point: UnitPoint, scale: Double,
                       opacity: Double, in size: CGSize) -> some View {
        let radius = min(size.width, size.height) * scale
        return Ellipse()
            .fill(
                RadialGradient(colors: [color.opacity(opacity), .clear],
                               center: .center, startRadius: 0, endRadius: radius * 0.5)
            )
            .frame(width: radius * 1.5, height: radius)
            .rotationEffect(.degrees(Self.axisDegrees))
            .position(x: size.width * point.x, y: size.height * point.y)
            .blur(radius: 55)
    }

    /// The diffuse light of the band itself, distinct from the stars resolved
    /// out of it.
    private func galacticBand(in size: CGSize) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [Color(red: 0.92, green: 0.88, blue: 1.0).opacity(0.16), .clear],
                    center: .center, startRadius: 0, endRadius: size.height * 0.30
                )
            )
            .frame(width: size.width * 2.0, height: size.height * 0.46)
            .rotationEffect(.degrees(Self.axisDegrees))
            .position(x: size.width * Self.core.x, y: size.height * Self.core.y)
            .blur(radius: 30)
    }

    /// The dark band across the middle. Subtractive, so it is drawn with
    /// `.destinationOut` rather than as a black shape, which over `plusLighter`
    /// would do nothing at all.
    private func dustLane(in size: CGSize) -> some View {
        Ellipse()
            .fill(
                LinearGradient(colors: [.clear, .black.opacity(0.85), .clear],
                               startPoint: .leading, endPoint: .trailing)
            )
            .frame(width: size.width * 1.9, height: size.height * 0.10)
            .rotationEffect(.degrees(Self.axisDegrees))
            .position(x: size.width * Self.core.x, y: size.height * (Self.core.y + 0.02))
            .blur(radius: 18)
            .blendMode(.destinationOut)
    }

    private func coreGlow(in size: CGSize) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.96, blue: 0.86).opacity(0.38),
                        Color(red: 1.0, green: 0.80, blue: 0.55).opacity(0.12),
                        .clear
                    ],
                    center: .center, startRadius: 0, endRadius: size.height * 0.16
                )
            )
            .frame(width: size.width * 0.62, height: size.height * 0.20)
            .rotationEffect(.degrees(Self.axisDegrees))
            .position(x: size.width * Self.core.x, y: size.height * Self.core.y)
            .blur(radius: 26)
    }

    // MARK: - The field

    private struct Star {
        let x: Double
        let y: Double
        let radius: Double
        let opacity: Double
        let tint: Color
    }

    private static let stars: [Star] = generate(count: 340)

    private static let tints: [Color] = [
        .white, .white, .white,
        Color(red: 0.80, green: 0.86, blue: 1.0),
        Color(red: 1.0, green: 0.90, blue: 0.80),
        Color(red: 0.95, green: 0.82, blue: 1.0)
    ]

    private static func generate(count: Int) -> [Star] {
        var rng = SeededGenerator(seed: 0x6A1A_5C07)
        let radians = axisDegrees * .pi / 180
        let along = (x: cos(radians), y: sin(radians))
        let across = (x: -along.y, y: along.x)

        return (0..<count).map { _ in
            let clustered = Double.random(in: 0...1, using: &rng) < 0.66
            var x: Double
            var y: Double

            if clustered {
                // Distance from the axis is cubed, so most of these land in the
                // band and a few stray out of it. A uniform spread would draw a
                // stripe with hard edges.
                let travel = Double.random(in: -1.0...1.0, using: &rng)
                let drift = Double.random(in: -1.0...1.0, using: &rng)
                let offset = pow(abs(drift), 3) * (drift < 0 ? -1 : 1) * 0.34
                x = core.x + along.x * travel * 0.95 + across.x * offset
                y = core.y + along.y * travel * 0.95 + across.y * offset
            } else {
                x = Double.random(in: 0...1, using: &rng)
                y = Double.random(in: 0...1, using: &rng)
            }

            // Wrap rather than clamp: clamping piles strays onto the edges in a
            // visible line.
            x = x.truncatingRemainder(dividingBy: 1.0)
            y = y.truncatingRemainder(dividingBy: 1.0)
            if x < 0 { x += 1 }
            if y < 0 { y += 1 }

            let brightness = pow(Double.random(in: 0...1, using: &rng), 3)
            return Star(
                x: x, y: y,
                radius: 0.4 + brightness * 1.5,
                opacity: (clustered ? 0.18 : 0.26) + brightness * 0.68,
                tint: tints[Int.random(in: 0..<tints.count, using: &rng)]
            )
        }
    }
}
