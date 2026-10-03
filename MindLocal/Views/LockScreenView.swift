import SwiftUI

/// What covers the journal while it is locked.
///
/// Opaque on purpose, and it takes the theme's own background rather than a
/// blur: a blurred journal still shows the shape of a page and the colour of a
/// mood, and the point of the lock is that a shoulder learns nothing.
///
/// It also sits over the app while the phone is merely inactive, not only while
/// locked, because iOS photographs the screen on the way to the app switcher.
struct LockScreenView: View {
    var onUnlock: () async -> Void

    var body: some View {
        ZStack {
            AlbumTheme.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(AlbumTheme.accent)

                Text("InnerSage")
                    .font(AlbumTheme.heading(.title))
                    .foregroundStyle(AlbumTheme.ink)

                Button {
                    Task { await onUnlock() }
                } label: {
                    Text("Unlock with \(AppLock.biometryName)")
                        .padding(.horizontal, 20)
                }
                .buttonStyle(AlbumPrimaryButtonStyle())
                .controlSize(.large)
                .padding(.top, 4)
            }
            .padding(32)
        }
    }
}
