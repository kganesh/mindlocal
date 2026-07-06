import SwiftUI

/// App settings. Currently read-aloud voice; room to grow.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Read Aloud") {
                    NavigationLink {
                        VoicePicker()
                    } label: {
                        Label("Voice", systemImage: "waveform")
                    }
                }
                Section {
                    LabeledContent("Version", value: "1.0")
                } footer: {
                    Text("MindLocal keeps your decisions and experiences on your device. Only weather forecasts for outdoor events use the network.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
