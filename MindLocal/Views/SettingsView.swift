import SwiftUI
import SwiftData

/// App settings: the nightly journal reminder and data management.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderHour")    private var reminderHour = 22   // 10 PM
    @AppStorage("reminderMinute")  private var reminderMinute = 0
    @AppStorage(HealthService.connectedKey) private var healthConnected = false

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

                if HealthService.isAvailable {
                    Section {
                        if healthConnected {
                            Label("Apple Health connected", systemImage: "heart.fill")
                                .foregroundStyle(.pink)
                        } else {
                            Button {
                                Task { healthConnected = await HealthService.shared.requestAuthorization() }
                            } label: {
                                Label("Connect Apple Health", systemImage: "heart")
                            }
                        }
                    } header: {
                        Text("Health")
                    } footer: {
                        Text("Adds your sleep, steps, and workouts as gentle context on entries and mood trends. Read-only and kept on your device.")
                    }
                }

                #if DEBUG
                Section {
                    Button(role: .destructive) {
                        confirmingWipe = true
                    } label: {
                        Label("Wipe All Data", systemImage: "trash")
                    }
                } header: {
                    Text("Data (Dev)")
                } footer: {
                    Text("Permanently deletes all entries, events, and people from this device. This can't be undone.")
                }
                #endif

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
        deleteAll(Experience.self)   // cascades its decisions
        deleteAll(Decision.self)
        deleteAll(OptionConsidered.self)
        deleteAll(Outcome.self)
        deleteAll(Event.self)
        deleteAll(PersonRelationship.self)
        deleteAll(Person.self)
        try? modelContext.save()
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        let items = (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
        for item in items { modelContext.delete(item) }
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
