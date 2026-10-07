import SwiftUI

/// Settings → Read-Aloud. Apple's on-device voice is the only engine, so this
/// screen is the voice picker and a line saying where better voices come from.
struct ReadAloudSettingsView: View {

    var body: some View {
        List {
            Section {
                NavigationLink("Apple Voices") { VoicePicker() }
            } footer: {
                Text("Entries and answers are read aloud with Apple's on-device voice. Enhanced and Premium voices download in Settings → Accessibility → Spoken Content.")
            }
        }
        .albumScreen()
        .navigationTitle("Read-Aloud")
        .navigationBarTitleDisplayMode(.inline)
    }
}
