import SwiftUI

/// App settings. Read-aloud voice + the nightly journal reminder.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderHour")    private var reminderHour = 22   // 10 PM
    @AppStorage("reminderMinute")  private var reminderMinute = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Nightly reminder", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Time", selection: reminderTime, displayedComponents: [.hourAndMinute])
                    }
                } header: {
                    Text("Daily Journal")
                } footer: {
                    Text("A gentle nudge to record your day. Default 10:00 PM.")
                }

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
                    Text("MindLocal keeps your journal on your device. Only weather forecasts for outdoor events use the network.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: reminderEnabled) { _, _ in applyReminder() }
            .onChange(of: reminderHour)    { _, _ in applyReminder() }
            .onChange(of: reminderMinute)  { _, _ in applyReminder() }
        }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? Date()
        } set: { newValue in
            let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = c.hour ?? 22
            reminderMinute = c.minute ?? 0
        }
    }

    private func applyReminder() {
        Task {
            if reminderEnabled {
                await DailyReminderService.shared.schedule(hour: reminderHour, minute: reminderMinute)
            } else {
                DailyReminderService.shared.cancel()
            }
        }
    }
}
