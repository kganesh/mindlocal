import SwiftUI
import UIKit

/// Shared colors adapt together so the journal stays readable in both appearances.
enum AlbumTheme {
    // The three planes need visible steps between them or the screen reads as
    // one flat tone — especially in an empty state, where almost everything on
    // screen is background or wash and nothing advances or recedes.
    //
    // Dark was 1C2420 / 28332C / 344238: about twelve points apart per channel,
    // inside an already narrow band. Deepening the background widens the whole
    // range without making the raised surfaces glow, which would break the
    // muted paper feel.
    //
    // Light had the opposite problem — surface (FFFDF8) sat barely above
    // background (F8F6F0), so cards never looked lifted off the page.
    // The surfaces are deliberately NEUTRAL, not green.
    //
    // When background, surface, wash, accent and secondary all share one hue,
    // the eye has only lightness to work with and the screen reads as a single
    // flat colour — "everything is sort of green". Greens then stop looking
    // green, because there is nothing un-green to compare them against.
    //
    // So the walls are warm neutral — echoing the cream paper of light mode —
    // and the colour lives in the accents: sage for actions, terracotta
    // (dateAccent) for dates. Both now have something to contrast with.
    static let background = adaptive(light: 0xF1EDE4, dark: 0x1A1815)
    static let surface = adaptive(light: 0xFFFDF8, dark: 0x252220)
    static let accent = adaptive(light: 0x245540, dark: 0xBCD6C0)
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x183326)
    static let ink = adaptive(light: 0x2A2722, dark: 0xF2EFE7)
    static let secondary = adaptive(light: 0x6B655C, dark: 0xB5AFA5)
    static let wash = adaptive(light: 0xE8E3D8, dark: 0x312D29)
    static let rule = adaptive(light: 0xD8D2C4, dark: 0x423D37)
    static let dateAccent = adaptive(light: 0x9C4B36, dark: 0xE5AA91)

    /// Spacing scale.
    ///
    /// The theme shared colour and type but not spacing, so each screen picked
    /// its own padding and stack gaps. That is why the layouts can look
    /// individually reasonable and still feel unsettled together — the vertical
    /// rhythm never repeats, and the eye reads the inconsistency without being
    /// able to name it.
    enum Space {
        /// Between tightly related lines — a label and its value.
        static let tight: CGFloat = 6
        /// Within a component — rows of a card.
        static let inner: CGFloat = 12
        /// Between components inside a section.
        static let between: CGFloat = 20
        /// Between major sections of a screen.
        static let section: CGFloat = 32
        /// Screen edge inset.
        static let margin: CGFloat = 24
    }

    static func heading(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif, weight: .regular)
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

struct AlbumHeading: View {
    var eyebrow: String? = nil
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AlbumTheme.dateAccent)
            }
            Text(title)
                .font(AlbumTheme.heading())
                .foregroundStyle(AlbumTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AlbumTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A rounded-square icon container.
///
/// Borrowed structurally from ResumeLocal's list rows, where every item carries
/// one: they give the eye an anchor per row and stop a column of text reading as
/// a wall. Borrowed structurally only — ResumeLocal fills them with saturated
/// blue on near-black, which suits a utility. Here they take the album palette,
/// so the device is shared but the voice is not.
struct AlbumIconTile: View {
    let symbol: String
    var tint: Color = AlbumTheme.accent
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct AlbumPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minHeight: 48)
            .foregroundStyle(isEnabled ? AlbumTheme.onAccent : AlbumTheme.secondary)
            .background(isEnabled ? AlbumTheme.accent : AlbumTheme.wash, in: RoundedRectangle(cornerRadius: 24))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct AlbumTag: View {
    let title: String
    var symbol: String? = nil

    var body: some View {
        Group {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .font(.caption)
        .foregroundStyle(AlbumTheme.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AlbumTheme.wash, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AlbumMonogram: View {
    let name: String
    @ScaledMetric(relativeTo: .title2) private var diameter = 48.0

    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
            .font(AlbumTheme.heading(.title2))
            .foregroundStyle(AlbumTheme.accent)
            .frame(width: diameter, height: diameter)
            .background(AlbumTheme.wash, in: Circle())
            .accessibilityHidden(true)
    }
}

private struct AlbumScreenModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(AlbumTheme.background.ignoresSafeArea())
            .foregroundStyle(AlbumTheme.ink)
            .tint(AlbumTheme.accent)
            .toolbarBackground(AlbumTheme.background, for: .navigationBar)
            // Setting the colour alone leaves the bar in its scroll-edge state,
            // where it is transparent and scroll content slides underneath it.
            // That is what sheared the top off the "+" button and hid the date
            // eyebrow on the Today screen entirely.
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func albumScreen() -> some View {
        modifier(AlbumScreenModifier())
    }
}
