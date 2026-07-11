import CoreText
import Foundation

/// Registers the app's bundled diary fonts (Caveat) with the process at launch.
///
/// The project uses a generated Info.plist, whose `INFOPLIST_KEY_*` allow-list
/// doesn't include `UIAppFonts`, so we can't declare the fonts there. Instead we
/// register the bundled TTFs directly with Core Text — same effect, no plist.
enum FontRegistration {
    static func registerBundledFonts() {
        for name in ["Caveat-Regular", "Caveat-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
