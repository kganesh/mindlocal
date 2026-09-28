import SwiftUI

/// Choosing a theme. Pushed from Settings, so no NavigationStack of its own.
///
/// It was a section inside Settings, above the nightly reminder and the voice
/// engines. A screen rather than a section because the rows are the tallest
/// thing in that list — each one carries a painting of what it does — and
/// because a theme is tried, lived with and changed again, unlike the settings
/// around it.
struct ThemeSettingsView: View {
    @AppStorage(AlbumTheme.paletteKey) private var paletteID = AlbumPalette.album.id

    var body: some View {
        List {
            Section {
                ForEach(AlbumPalette.all) { palette in
                    Button {
                        paletteID = palette.id
                    } label: {
                        row(palette)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AlbumTheme.surface)
                }
            } footer: {
                Text("Album, Ink and Dusk follow your light and dark setting. A painted theme keeps the appearance its backdrop needs.")
            }
        }
        .albumScreen()
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ palette: AlbumPalette) -> some View {
        HStack(spacing: 14) {
            // The page, then its two colours. What separates one theme from
            // another is the relationship between page, accent and date, not
            // any single colour.
            backdropPreview(palette)
            VStack(alignment: .leading, spacing: 6) {
                Text(palette.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AlbumTheme.ink)
                HStack(spacing: 6) {
                    swatch(palette.accent)
                    swatch(palette.dateAccent)
                }
            }
            Spacer()
            if paletteID == palette.id {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AlbumTheme.accent)
            }
        }
        .padding(.vertical, 4)
    }

    private func swatch(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(AlbumTheme.rule, lineWidth: 1))
    }

    /// A miniature of what the theme actually paints. A colour chip cannot tell
    /// Night Sky, Ocean, Galaxy and Rain apart — all four are near-black — and
    /// the backdrop is the whole reason to pick one.
    ///
    /// Rendered at something near screen proportions and then scaled down,
    /// rather than laid out small. The fields are drawn in absolute point
    /// sizes, so a half-point star placed straight into a small box would come
    /// out the same size as one on a full screen and the tile would read as
    /// noise instead of as a picture of the theme.
    private func backdropPreview(_ palette: AlbumPalette) -> some View {
        let width: CGFloat = 188
        let height: CGFloat = 116
        let scale: CGFloat = 0.42

        return Group {
            switch palette.backdrop {
            case .plain:    palette.background
            case .nightSky: AlbumStarfield()
            case .ocean:    AlbumOceanDepths()
            case .galaxy:   AlbumGalaxy()
            case .rain:     AlbumRainfall()
            case .rainOnGlass: AlbumRainOnGlass()
            case .halloween: AlbumHalloween()
            case .christmasLights: AlbumChristmasLights()
            case .diwali:   AlbumDiwaliDiyas()
            case .sunrise:  AlbumSunrise()
            case .blueSky:  AlbumBlueSky()
            }
        }
        .frame(width: width, height: height)
        // Two themes can share a backdrop, so the thing that tells them apart
        // has to be in the picture. Drawn before the scale-down, like
        // everything else in the tile.
        .overlay(alignment: .bottomTrailing) {
            if palette.companion {
                AlbumMoonCompanion(part: .head, diameter: 44)
                    .offset(x: 6, y: 10)
            }
        }
        .scaleEffect(scale)
        .frame(width: width * scale, height: height * scale)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AlbumTheme.rule, lineWidth: 1))
    }
}
