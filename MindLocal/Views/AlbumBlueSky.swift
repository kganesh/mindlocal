import SwiftUI

/// The painted backdrop for the Blue Sky theme: a clear day with cumulus.
///
/// Not currently offered in the picker — `AlbumPalette.all` leaves it out. It
/// stays wired to its palette and its backdrop case, so returning it is one
/// line there rather than a resurrection here.
///
/// The first painted backdrop that is light rather than dark, which is the
/// whole reason `AlbumBackdrop` carries an appearance instead of every painted
/// theme assuming one.
///
/// Built the same way as the others — seeded once, drawn once, nothing
/// animating. Depth comes from haze: clouds nearer the horizon are smaller,
/// flatter, paler and blurrier, because that is what distance does to them.
struct AlbumBlueSky: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.192, green: 0.502, blue: 0.776),
                    Color(red: 0.443, green: 0.702, blue: 0.886),
                    Color(red: 0.792, green: 0.894, blue: 0.945)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                let size = proxy.size

                // Sun off the top-right corner. Not a disc — a disc in the
                // corner of every screen becomes a blemish you notice once and
                // then cannot stop noticing.
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 1.0, green: 0.98, blue: 0.88).opacity(0.75), .clear],
                            center: .center, startRadius: 0, endRadius: size.height * 0.28
                        )
                    )
                    .frame(width: size.width * 1.2, height: size.height * 0.6)
                    .position(x: size.width * 0.92, y: size.height * 0.04)
                    .blur(radius: 40)

                ForEach(Self.clouds.indices, id: \.self) { index in
                    cloud(Self.clouds[index], in: size)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// One cumulus: overlapping ellipses with a flat base, blurred as a group.
    /// Blurring the group rather than each puff is what fuses them into a
    /// single cloud instead of a pile of circles.
    private func cloud(_ cloud: Cloud, in size: CGSize) -> some View {
        let width = size.width * cloud.width
        let height = width * 0.42

        return ZStack {
            ForEach(cloud.puffs.indices, id: \.self) { index in
                let puff = cloud.puffs[index]
                Ellipse()
                    .fill(Color.white.opacity(cloud.opacity))
                    .frame(width: width * puff.width, height: height * puff.height)
                    .offset(x: width * puff.x, y: height * puff.y)
            }
        }
        .compositingGroup()
        .blur(radius: cloud.blur)
        .frame(width: width, height: height)
        .position(x: size.width * cloud.x, y: size.height * cloud.y)
    }

    // MARK: - The field

    private struct Puff {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    private struct Cloud {
        let x: Double
        let y: Double
        let width: Double
        let opacity: Double
        let blur: Double
        let puffs: [Puff]
    }

    private static let clouds: [Cloud] = generate()

    /// Positions are fixed rather than random. Six clouds is few enough that a
    /// bad roll — two overlapping, or a bare stripe across the middle — shows,
    /// and the generator is only used for the puffs inside each one.
    private static func generate() -> [Cloud] {
        var rng = SeededGenerator(seed: 0x51C0_D5E7)
        let placements: [(x: Double, y: Double, width: Double, opacity: Double, blur: Double, puffs: Int)] = [
            (0.22, 0.14, 0.52, 0.92, 7,  6),
            (0.78, 0.30, 0.40, 0.85, 8,  5),
            (0.34, 0.47, 0.34, 0.72, 10, 5),
            (0.86, 0.62, 0.30, 0.58, 12, 4),
            (0.18, 0.74, 0.26, 0.46, 14, 4),
            (0.58, 0.88, 0.22, 0.34, 16, 4)
        ]

        return placements.map { place in
            let puffs = (0..<place.puffs).map { index -> Puff in
                let across = Double(index) / Double(max(place.puffs - 1, 1)) - 0.5
                return Puff(
                    // Spread along the cloud with a little jitter, and sit the
                    // tallest puffs in the middle so the top domes and the base
                    // stays flat — which is what makes it a cloud and not a
                    // cotton ball.
                    x: across * 0.72 + Double.random(in: -0.04...0.04, using: &rng),
                    y: Double.random(in: -0.02...0.10, using: &rng) - (0.28 * (1 - abs(across) * 1.6)),
                    width: Double.random(in: 0.34...0.52, using: &rng),
                    height: Double.random(in: 0.70...1.25, using: &rng) * (1 - abs(across) * 0.45)
                )
            }
            return Cloud(x: place.x, y: place.y, width: place.width,
                         opacity: place.opacity, blur: place.blur, puffs: puffs)
        }
    }
}
