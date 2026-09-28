import SwiftUI

/// The painted backdrop for the Planets theme: a gas giant cropped by the
/// bottom corner, a ringed world further out, a moon between them.
///
/// Different from Galaxy, which is a field of stars with structure in it. This
/// is bodies with edges, and what makes them read as bodies is lighting: every
/// one is lit from the same upper-right point and falls into shadow away from
/// it. A flat disc is a coin however carefully it is coloured.
///
/// Stars are deliberately sparse here. Galaxy already does a crowded sky, and
/// a planet needs empty space around it to look large.
///
/// Same rules as the other painted backdrops: a graded wash, seeded field
/// generated once, nothing animating.
struct AlbumPlanets: View {

    /// Where the light comes from, as an offset within a body's own radius.
    /// One direction for everything on screen, because two would read as two
    /// suns.
    private static let lightOffset = CGSize(width: 0.55, height: -0.55)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.020, green: 0.027, blue: 0.059),
                    Color(red: 0.035, green: 0.043, blue: 0.086),
                    Color(red: 0.027, green: 0.031, blue: 0.063),
                    Color(red: 0.012, green: 0.016, blue: 0.039)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                for star in Self.stars {
                    let centre = CGPoint(x: star.x * size.width, y: star.y * size.height)
                    context.fill(
                        Path(ellipseIn: CGRect(x: centre.x - star.radius, y: centre.y - star.radius,
                                               width: star.radius * 2, height: star.radius * 2)),
                        with: .color(.white.opacity(star.opacity))
                    )
                }

                // Far to near, so a nearer body can overlap one behind it.
                drawRinged(in: &context, size: size)
                drawMoon(in: &context, size: size)
                drawGiant(in: &context, size: size)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Bodies

    /// The gas giant, cropped by the corner. Cropping is what gives it scale:
    /// a whole planet on screen is a marble, and a piece of one is a world.
    private func drawGiant(in context: inout GraphicsContext, size: CGSize) {
        let radius = size.width * 0.46
        let centre = CGPoint(x: size.width * 0.10, y: size.height * 0.98)
        let disc = CGRect(x: centre.x - radius, y: centre.y - radius,
                          width: radius * 2, height: radius * 2)

        context.drawLayer { layer in
            layer.clip(to: Path(ellipseIn: disc))
            layer.fill(Path(disc), with: .color(Color(red: 0.42, green: 0.29, blue: 0.24)))

            // Bands, wider near the equator and thinner towards the pole, which
            // is roughly what banding on a rotating body looks like.
            let bands: [(offset: Double, height: Double, tint: Color)] = [
                (-0.52, 0.10, Color(red: 0.52, green: 0.38, blue: 0.30)),
                (-0.26, 0.15, Color(red: 0.36, green: 0.24, blue: 0.21)),
                (0.02,  0.19, Color(red: 0.56, green: 0.42, blue: 0.32)),
                (0.34,  0.13, Color(red: 0.34, green: 0.23, blue: 0.20)),
                (0.62,  0.09, Color(red: 0.48, green: 0.34, blue: 0.27))
            ]
            for band in bands {
                let rect = CGRect(x: disc.minX - radius * 0.1,
                                  y: centre.y + radius * band.offset,
                                  width: disc.width + radius * 0.2,
                                  height: radius * band.height)
                layer.fill(Path(ellipseIn: rect), with: .color(band.tint.opacity(0.85)))
            }

            shade(disc, radius: radius, centre: centre, in: &layer)
        }
    }

    /// The ringed world. The ring is drawn in three passes — behind, planet,
    /// then the near arc over the top — because a ring that passes wholly in
    /// front or wholly behind reads as a hoop resting on a ball.
    private func drawRinged(in context: inout GraphicsContext, size: CGSize) {
        let radius = size.width * 0.115
        let centre = CGPoint(x: size.width * 0.76, y: size.height * 0.22)
        let disc = CGRect(x: centre.x - radius, y: centre.y - radius,
                          width: radius * 2, height: radius * 2)
        let ring = CGRect(x: centre.x - radius * 2.1, y: centre.y - radius * 0.52,
                          width: radius * 4.2, height: radius * 1.04)
        let tilt = Angle.degrees(-16)
        let ringColor = Color(red: 0.78, green: 0.72, blue: 0.60)

        func strokeRing(_ target: inout GraphicsContext, opacity: Double) {
            target.translateBy(x: centre.x, y: centre.y)
            target.rotate(by: tilt)
            target.translateBy(x: -centre.x, y: -centre.y)
            target.stroke(Path(ellipseIn: ring),
                          with: .color(ringColor.opacity(opacity)),
                          lineWidth: radius * 0.30)
            target.stroke(Path(ellipseIn: ring.insetBy(dx: -radius * 0.26, dy: -radius * 0.07)),
                          with: .color(ringColor.opacity(opacity * 0.45)),
                          lineWidth: radius * 0.12)
        }

        context.drawLayer { layer in strokeRing(&layer, opacity: 0.55) }

        context.drawLayer { layer in
            layer.clip(to: Path(ellipseIn: disc))
            layer.fill(Path(disc), with: .color(Color(red: 0.62, green: 0.54, blue: 0.40)))
            layer.fill(Path(ellipseIn: CGRect(x: disc.minX, y: centre.y - radius * 0.12,
                                              width: disc.width, height: radius * 0.30)),
                       with: .color(Color(red: 0.52, green: 0.44, blue: 0.32).opacity(0.7)))
            shade(disc, radius: radius, centre: centre, in: &layer)
        }

        // The near arc: the half of the ring below the planet's centre, which
        // is the part that crosses in front of it.
        context.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: 0, y: centre.y, width: size.width, height: size.height)))
            strokeRing(&layer, opacity: 0.62)
        }
    }

    private func drawMoon(in context: inout GraphicsContext, size: CGSize) {
        let radius = size.width * 0.030
        let centre = CGPoint(x: size.width * 0.33, y: size.height * 0.46)
        let disc = CGRect(x: centre.x - radius, y: centre.y - radius,
                          width: radius * 2, height: radius * 2)
        context.drawLayer { layer in
            layer.clip(to: Path(ellipseIn: disc))
            layer.fill(Path(disc), with: .color(Color(red: 0.55, green: 0.57, blue: 0.62)))
            shade(disc, radius: radius, centre: centre, in: &layer)
        }
    }

    /// The shadow half. A gradient offset away from the light, dark and soft,
    /// so the terminator is a fade rather than a line. Clipped by the caller to
    /// the body it belongs to.
    private func shade(_ disc: CGRect, radius: CGFloat, centre: CGPoint,
                       in context: inout GraphicsContext) {
        let lit = CGPoint(x: centre.x + radius * Self.lightOffset.width,
                          y: centre.y + radius * Self.lightOffset.height)
        context.fill(
            Path(disc),
            with: .radialGradient(
                Gradient(colors: [.clear,
                                  Color.black.opacity(0.35),
                                  Color.black.opacity(0.88)]),
                center: lit, startRadius: radius * 0.35, endRadius: radius * 2.15
            )
        )
    }

    // MARK: - The field

    private struct Star {
        let x: Double
        let y: Double
        let radius: Double
        let opacity: Double
    }

    private static let stars: [Star] = {
        var rng = SeededGenerator(seed: 0x71A_5E75)
        return (0..<110).map { _ in
            let brightness = pow(Double.random(in: 0...1, using: &rng), 3)
            return Star(
                x: Double.random(in: 0...1, using: &rng),
                y: Double.random(in: 0...1, using: &rng),
                radius: 0.4 + brightness * 1.2,
                opacity: 0.16 + brightness * 0.6
            )
        }
    }()
}
