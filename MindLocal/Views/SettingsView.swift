import SwiftUI
import SwiftData

/// App settings: the nightly journal reminder and data management.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderHour")    private var reminderHour = 22   // 10 PM
    @AppStorage("reminderMinute")  private var reminderMinute = 0

    @State private var confirmingWipe = false

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

                Section {
                    Button(role: .destructive) {
                        confirmingWipe = true
                    } label: {
                        Label("Wipe All Data", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Permanently deletes all entries, events, and people from this device. This can't be undone.")
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
            .alert("Wipe all data?", isPresented: $confirmingWipe) {
                Button("Delete Everything", role: .destructive) { wipeAllData() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes all entries, events, and people. It can't be undone.")
            }
        }
    }

    private func wipeAllData() {
        try? modelContext.delete(model: Experience.self)
        try? modelContext.delete(model: Decision.self)
        try? modelContext.delete(model: OptionConsidered.self)
        try? modelContext.delete(model: Outcome.self)
        try? modelContext.delete(model: Event.self)
        try? modelContext.delete(model: PersonRelationship.self)
        try? modelContext.delete(model: Person.self)
        try? modelContext.save()
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
