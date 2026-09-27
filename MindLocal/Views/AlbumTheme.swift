import SwiftUI
import UIKit

/// What is painted behind a screen. Every theme so far is a flat colour; Night
/// Sky is not, and the difference has to live on the palette so that adding a
/// theme still means adding a palette and touching no view.
enum AlbumBackdrop: Hashable {
    case plain
    case nightSky
    case ocean
    case galaxy
    case rain
}

/// A complete set of colours. Adding a theme means adding one of these, not
/// touching any view.
struct AlbumPalette: Identifiable, Hashable {
    let id: String
    let name: String
    let background: Color
    let surface: Color
    let accent: Color
    let onAccent: Color
    let ink: Color
    let secondary: Color
    let wash: Color
    let rule: Color
    let dateAccent: Color
    /// Defaulted so the flat-colour palettes below are unchanged.
    var backdrop: AlbumBackdrop = .plain

    /// A painted backdrop only works dark. Light mode would put a starfield or
    /// a deep ocean behind cream cards, so these palettes opt the whole app
    /// into the dark appearance rather than defining a light variant they
    /// cannot honour.
    var forcesDarkAppearance: Bool { backdrop != .plain }

    static let all: [AlbumPalette] = [.album, .ink, .dusk, .night, .ocean, .galaxy, .rain]

    static func named(_ id: String?) -> AlbumPalette {
        all.first { $0.id == id } ?? .album
    }

    /// Warm neutral paper, sage actions, terracotta dates. The default.
    static let album = AlbumPalette(
        id: "album", name: "Album",
        background: hex(light: 0xF1EDE4, dark: 0x1A1815),
        surface:    hex(light: 0xFFFDF8, dark: 0x252220),
        accent:     hex(light: 0x245540, dark: 0xBCD6C0),
        onAccent:   hex(light: 0xFFFFFF, dark: 0x183326),
        ink:        hex(light: 0x2A2722, dark: 0xF2EFE7),
        secondary:  hex(light: 0x6B655C, dark: 0xB5AFA5),
        wash:       hex(light: 0xE8E3D8, dark: 0x312D29),
        rule:       hex(light: 0xD8D2C4, dark: 0x423D37),
        dateAccent: hex(light: 0x9C4B36, dark: 0xE5AA91)
    )

    /// Near-monochrome. Deep charcoal, a single blue-black accent, amber dates.
    /// For reading rather than browsing.
    static let ink = AlbumPalette(
        id: "ink", name: "Ink",
        background: hex(light: 0xF4F4F2, dark: 0x141416),
        surface:    hex(light: 0xFFFFFF, dark: 0x1F1F22),
        accent:     hex(light: 0x2B3A4A, dark: 0xA9C0D6),
        onAccent:   hex(light: 0xFFFFFF, dark: 0x16202B),
        ink:        hex(light: 0x1B1B1D, dark: 0xF0F0F2),
        secondary:  hex(light: 0x66666B, dark: 0xAAAAB0),
        wash:       hex(light: 0xE9E9E7, dark: 0x2A2A2E),
        rule:       hex(light: 0xD9D9D6, dark: 0x3A3A3F),
        dateAccent: hex(light: 0x8A5A1E, dark: 0xE2B472)
    )

    /// Cooler and dimmer, plum accents. Easier at night.
    static let dusk = AlbumPalette(
        id: "dusk", name: "Dusk",
        background: hex(light: 0xF2F0F4, dark: 0x17151C),
        surface:    hex(light: 0xFFFFFF, dark: 0x221F29),
        accent:     hex(light: 0x543A6B, dark: 0xC6AEDC),
        onAccent:   hex(light: 0xFFFFFF, dark: 0x241A2E),
        ink:        hex(light: 0x25222B, dark: 0xF0EDF3),
        secondary:  hex(light: 0x666070, dark: 0xB2AABB),
        wash:       hex(light: 0xE8E4EC, dark: 0x2D2836),
        rule:       hex(light: 0xD6D0DC, dark: 0x3E3748),
        dateAccent: hex(light: 0x9A4A5E, dark: 0xE8A2B4)
    )

    /// A night sky: deep blue-black walls, starlight blue actions, a warm
    /// moon-gold for dates. Both hex values are identical on every token
    /// because this theme is dark in either system appearance.
    static let night = AlbumPalette(
        id: "night", name: "Night Sky",
        background: hex(light: 0x070A15, dark: 0x070A15),
        surface:    hex(light: 0x141B31, dark: 0x141B31),
        accent:     hex(light: 0x9DB8F2, dark: 0x9DB8F2),
        onAccent:   hex(light: 0x0A1024, dark: 0x0A1024),
        ink:        hex(light: 0xE9ECF8, dark: 0xE9ECF8),
        secondary:  hex(light: 0x99A2C2, dark: 0x99A2C2),
        wash:       hex(light: 0x1C2440, dark: 0x1C2440),
        rule:       hex(light: 0x2B3558, dark: 0x2B3558),
        dateAccent: hex(light: 0xF0C67D, dark: 0xF0C67D),
        backdrop: .nightSky
    )

    /// Underwater: teal walls that deepen downward, seafoam actions, and a warm
    /// coral for dates — the one thing on screen that is not blue-green, so
    /// dates still read as dates. Dark in either system appearance.
    static let ocean = AlbumPalette(
        id: "ocean", name: "Ocean",
        background: hex(light: 0x04161F, dark: 0x04161F),
        surface:    hex(light: 0x0C2C3A, dark: 0x0C2C3A),
        accent:     hex(light: 0x74D6CE, dark: 0x74D6CE),
        onAccent:   hex(light: 0x04211F, dark: 0x04211F),
        ink:        hex(light: 0xE4F3F4, dark: 0xE4F3F4),
        secondary:  hex(light: 0x93B4BE, dark: 0x93B4BE),
        wash:       hex(light: 0x12384A, dark: 0x12384A),
        rule:       hex(light: 0x1F4C5E, dark: 0x1F4C5E),
        dateAccent: hex(light: 0xF2A17F, dark: 0xF2A17F),
        backdrop: .ocean
    )

    /// Deep violet-black, lavender actions, a warm amber for dates picked up
    /// from the galactic core. Dark in either system appearance.
    static let galaxy = AlbumPalette(
        id: "galaxy", name: "Galaxy",
        background: hex(light: 0x0A0718, dark: 0x0A0718),
        surface:    hex(light: 0x1B1533, dark: 0x1B1533),
        accent:     hex(light: 0xC0A6F5, dark: 0xC0A6F5),
        onAccent:   hex(light: 0x130A29, dark: 0x130A29),
        ink:        hex(light: 0xEDE8F8, dark: 0xEDE8F8),
        secondary:  hex(light: 0xA69CC4, dark: 0xA69CC4),
        wash:       hex(light: 0x241C40, dark: 0x241C40),
        rule:       hex(light: 0x362C5A, dark: 0x362C5A),
        dateAccent: hex(light: 0xF3C07C, dark: 0xF3C07C),
        backdrop: .galaxy
    )

    /// Wet slate, petrichor green actions, lamplight amber for dates — the
    /// warm note the rain is lit by. Dark in either system appearance.
    static let rain = AlbumPalette(
        id: "rain", name: "Rain",
        background: hex(light: 0x0D1316, dark: 0x0D1316),
        surface:    hex(light: 0x1A2429, dark: 0x1A2429),
        accent:     hex(light: 0xA3C9AF, dark: 0xA3C9AF),
        onAccent:   hex(light: 0x102118, dark: 0x102118),
        ink:        hex(light: 0xE6EDEF, dark: 0xE6EDEF),
        secondary:  hex(light: 0x99A8AE, dark: 0x99A8AE),
        wash:       hex(light: 0x212D33, dark: 0x212D33),
        rule:       hex(light: 0x2F3D45, dark: 0x2F3D45),
        dateAccent: hex(light: 0xE9BB8E, dark: 0xE9BB8E),
        backdrop: .rain
    )

    private static func hex(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

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
    /// The active palette. Every token below reads from this, so swapping it
    /// changes the whole app.
    ///
    /// Stored as a raw value in UserDefaults rather than held in an observable
    /// object, because these tokens are statics read from 28 files. The root
    /// view watches the same key and re-renders the tree when it changes, which
    /// is what makes the swap take effect without rewriting every view.
    static var palette: AlbumPalette {
        AlbumPalette.named(UserDefaults.standard.string(forKey: paletteKey))
    }

    static let paletteKey = "albumPalette"

    static var background: Color { palette.background }
    static var surface: Color { palette.surface }
    static var accent: Color { palette.accent }
    static var onAccent: Color { palette.onAccent }
    static var ink: Color { palette.ink }
    static var secondary: Color { palette.secondary }
    static var wash: Color { palette.wash }
    static var rule: Color { palette.rule }
    static var dateAccent: Color { palette.dateAccent }

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
// MARK: - Semantic roles
//
// The tokens above name LEVELS: background, surface, wash, accent. Views then
// each decide which level a button or a field should be, which is why the same
// control ends up on `surface` in one screen and `wash` in another.
//
// These name ROLES instead. A view asks for AlbumTheme.Button.primaryFill and
// does not have to know or agree which level that is. Changing what a button
// looks like becomes one edit here rather than a search across 28 files, and a
// second palette later is a matter of repointing these, not rewriting views.
//
// Every value resolves to an existing token. Nothing new is introduced, so this
// changes no pixels on its own.

extension AlbumTheme {

    enum Button {
        /// The one action a screen wants you to take.
        static let primaryFill = AlbumTheme.accent
        static let primaryLabel = AlbumTheme.onAccent

        /// Everything else. Present, not competing.
        static let secondaryFill = AlbumTheme.wash
        static let secondaryLabel = AlbumTheme.accent
        static let secondaryBorder = AlbumTheme.rule

        /// Unavailable, not merely quiet — distinct from secondary on purpose,
        /// or a disabled primary reads as a secondary action you could take.
        static let disabledFill = AlbumTheme.wash
        static let disabledLabel = AlbumTheme.secondary

        /// Deleting an entry, clearing a journal. Warm rather than alarm-red, to
        /// sit with the palette without losing the warning.
        static let destructive = AlbumTheme.dateAccent
    }

    enum Field {
        /// Raised, so the place you type is distinct from the page it sits on.
        static let background = AlbumTheme.surface
        static let text = AlbumTheme.ink
        static let placeholder = AlbumTheme.secondary
        static let border = AlbumTheme.rule
        /// The only cue that keyboard input lands here rather than elsewhere.
        static let focusedBorder = AlbumTheme.accent
        /// Clear buttons and character counts, which should not compete with
        /// what has been typed.
        static let accessory = AlbumTheme.secondary
    }

    enum TabBar {
        /// Matches the page, so the bar reads as part of it rather than a shelf
        /// bolted underneath.
        static let background = AlbumTheme.background
        static let selectedIcon = AlbumTheme.accent
        static let selectedBackground = AlbumTheme.wash
        static let unselectedIcon = AlbumTheme.secondary
    }

    /// Depth, named by what it means rather than how light it is.
    enum Layer {
        /// The page itself.
        static let page = AlbumTheme.background
        /// Cards and fields sitting on the page.
        static let raised = AlbumTheme.surface
        /// Chips, pills, inset wells — recessed into it.
        static let sunken = AlbumTheme.wash
        static let hairline = AlbumTheme.rule
    }
}

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

/// A selectable filter pill.
///
/// Replaces a toolbar Menu, which hides the available filters behind a tap and
/// gives no indication of which one is active beyond a slightly different icon.
/// A row of capsules shows the options and the current state at once — the
/// pattern ResumeLocal uses for its status chips, in the album palette.
struct AlbumFilterCapsule: View {
    let label: String
    var symbol: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.caption)
                }
                Text(label).font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(isSelected ? AlbumTheme.Button.primaryLabel : AlbumTheme.Button.disabledLabel)
            .background(isSelected ? AlbumTheme.Button.primaryFill : AlbumTheme.Button.secondaryFill, in: Capsule())
            .overlay {
                Capsule().strokeBorder(isSelected ? .clear : AlbumTheme.Button.secondaryBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
            .foregroundStyle(isEnabled ? AlbumTheme.Button.primaryLabel : AlbumTheme.Button.disabledLabel)
            .background(isEnabled ? AlbumTheme.Button.primaryFill : AlbumTheme.Button.disabledFill,
                        in: RoundedRectangle(cornerRadius: 24))
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
            .background {
                switch AlbumTheme.palette.backdrop {
                case .plain:    AlbumTheme.background.ignoresSafeArea()
                case .nightSky: AlbumStarfield()
                case .ocean:    AlbumOceanDepths()
                case .galaxy:   AlbumGalaxy()
                case .rain:     AlbumRainfall()
                }
            }
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
