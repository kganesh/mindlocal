import SwiftUI

/// A moon leaning on the top edge of the writing card: head tipped to one side,
/// one arm stretched along the border, the lower third of its face behind it.
///
/// Awake on purpose. This is here to invite someone — a child especially — to
/// say what happened today, and a sleeping face says the opposite: do not
/// disturb. But only just awake: two dots and a small curve. A fuller eye was
/// tried, and at this size a drawn pupil stares rather than welcomes.
///
/// Drawn in two parts because it sits on both sides of the card. `head` goes in
/// the card's background so the border crosses the face; `arm` goes in its
/// overlay so it lies on top of that border. One view drawn once could only
/// ever be wholly in front or wholly behind, which is what made the first
/// attempt float above the card instead of leaning on it.
///
/// Shapes rather than an asset: it takes its colours from the active palette,
/// stays sharp at any size, and needs no artwork pipeline. Nothing moves — the
/// card underneath is where someone writes, and something animating in the
/// corner of the eye while you look for the next word is a cost paid for
/// decoration.
struct AlbumMoonCompanion: View {
    enum Part { case head, arm }

    var part: Part
    var diameter: CGFloat = 96

    private var moon: Color { AlbumTheme.dateAccent }
    private var ink: Color { AlbumTheme.background }

    /// Both parts share one width so their offsets can match, which is what
    /// keeps the palms under the face rather than beside it.
    private var boxWidth: CGFloat { diameter * 1.5 }

    var body: some View {
        Group {
            switch part {
            case .head: head
            case .arm:  arm
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Head

    /// Everything is placed in the moon's own square, so a coordinate is where
    /// it looks like it is. The first version drew the mouth from negative x in
    /// a frame whose origin is its top-left corner, and it landed off the side
    /// of the face.
    private var head: some View {
        ZStack {
            Circle().fill(moon)
            craters
            eyes
            smile
        }
        .frame(width: diameter, height: diameter)
        // Tipped towards the stretched arm. A small tilt with open eyes reads
        // as curious; the same tilt with closed ones reads as asleep.
        .rotationEffect(.degrees(-10))
        .frame(width: boxWidth, height: diameter)
    }

    /// Two small dots. Large eyes with catchlights were meant to read as
    /// friendly and came out staring — at this size, on a face this simple,
    /// the more you draw of an eye the more it looks at you.
    private var eyes: some View {
        ellipses(at: [0.37, 0.63], y: 0.44, radius: 0.042)
            .fill(ink)
            .frame(width: diameter, height: diameter)
    }

    /// Circles placed in the moon's own square, where a coordinate is where it
    /// looks like it is.
    private func ellipses(at xs: [Double], y: Double, radius: Double) -> Path {
        Path { path in
            for x in xs {
                path.addEllipse(in: CGRect(x: diameter * (x - radius),
                                           y: diameter * (y - radius),
                                           width: diameter * radius * 2,
                                           height: diameter * radius * 2))
            }
        }
    }

    /// A quadratic curve with its control point below the ends, so it bows
    /// downward into a smile.
    private var smile: some View {
        Path { path in
            path.move(to: CGPoint(x: diameter * 0.41, y: diameter * 0.60))
            path.addQuadCurve(to: CGPoint(x: diameter * 0.59, y: diameter * 0.60),
                              control: CGPoint(x: diameter * 0.50, y: diameter * 0.71))
        }
        .stroke(ink, style: StrokeStyle(lineWidth: diameter * 0.038, lineCap: .round))
        .frame(width: diameter, height: diameter)
    }

    /// Three, unevenly placed. An even scatter reads as a pattern rather than
    /// as a moon. Kept clear of the face.
    private var craters: some View {
        ZStack {
            ellipses(at: [0.24], y: 0.26, radius: 0.075).fill(ink.opacity(0.13))
            ellipses(at: [0.78], y: 0.30, radius: 0.048).fill(ink.opacity(0.13))
            ellipses(at: [0.72], y: 0.70, radius: 0.060).fill(ink.opacity(0.13))
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: - Arm

    /// One arm, laid along the border and stretching out past the face. The
    /// other is underneath. Two symmetrical hands read as gripping a ledge,
    /// which is a tenser thing than leaning on one.
    ///
    /// Its far end is the visible hand; the near end runs under the head, and
    /// since both are the same gold the join does not show.
    private var arm: some View {
        Capsule()
            .fill(moon)
            .frame(width: diameter * 1.02, height: diameter * 0.18)
            .frame(width: boxWidth, alignment: .leading)
    }
}

#Preview {
    ZStack {
        AlbumStarfield()
        VStack {
            Spacer()
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(AlbumTheme.surface)
                    .frame(height: 220)
                    .background(alignment: .top) {
                        AlbumMoonCompanion(part: .head).offset(y: -96 * 2 / 3)
                    }
                    .overlay(alignment: .top) {
                        AlbumMoonCompanion(part: .arm).offset(y: -96 * 0.09)
                    }
            }
            .padding(24)
            Spacer()
        }
    }
}
