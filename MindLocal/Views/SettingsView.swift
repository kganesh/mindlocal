import SwiftUI
import SwiftData

/// App settings: the nightly journal reminder and data management.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage(AlbumTheme.paletteKey) private var paletteID = AlbumPalette.album.id
    @AppStorage(AdviceGroundingSettings.enabledKey) private var groundedAnswersEnabled = false
    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderHour")    private var reminderHour = 22   // 10 PM
    @AppStorage("reminderMinute")  private var reminderMinute = 0
    @AppStorage(HealthService.connectedKey) private var healthConnected = false

    @State private var confirmingWipe = false

    private func swatch(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(AlbumTheme.rule, lineWidth: 1))
    }

    /// A miniature of what the theme actually paints. A colour chip cannot tell
    /// Night Sky, Ocean and Galaxy apart — all three are near-black — and the
    /// backdrop is the whole reason to pick one.
    ///
    /// Rendered at something near screen proportions and then scaled down,
    /// rather than laid out small. The fields are drawn in absolute point
    /// sizes, so a half-point star placed straight into a 47pt box would come
    /// out the same size as one on a full screen and the tile would read as
    /// noise instead of as a picture of the theme.
    private func backdropPreview(_ palette: AlbumPalette) -> some View {
        let width: CGFloat = 188
        let height: CGFloat = 116
        let scale: CGFloat = 0.26

        return Group {
            switch palette.backdrop {
            case .plain:    palette.background
            case .nightSky: AlbumStarfield()
            case .ocean:    AlbumOceanDepths()
            case .galaxy:   AlbumGalaxy()
            case .rain:     AlbumRainfall()
            }
        }
        .frame(width: width, height: height)
        .scaleEffect(scale)
        .frame(width: width * scale, height: height * scale)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(AlbumTheme.rule, lineWidth: 1))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AlbumPalette.all) { palette in
                        Button {
                            paletteID = palette.id
                        } label: {
                            HStack(spacing: 12) {
                                // The page, then its two colours. What
                                // separates one theme from another is the
                                // relationship between page, accent and date,
                                // not any single colour.
                                HStack(spacing: 8) {
                                    backdropPreview(palette)
                                    swatch(palette.accent)
                                    swatch(palette.dateAccent)
                                }
                                Text(palette.name)
                                    .foregroundStyle(AlbumTheme.ink)
                                Spacer()
                                if paletteID == palette.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AlbumTheme.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Theme")
                } footer: {
                    Text("Album, Ink and Dusk follow your light and dark setting. The painted themes stay dark.")
                }

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
                    Toggle("Grounded Answers", isOn: $groundedAnswersEnabled)
                } header: {
                    Text("Advise (Dev)")
                } footer: {
                    Text("Asks the model to cite the evidence it used, then checks those citations against the context it was actually given. Findings appear under the answer in Advise.")
                }

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
                    NavigationLink {
                        TranscriptionSettingsView()
                    } label: {
                        LabeledContent("Transcription", value: SpeechEngine.currentEngineName)
                    }
                    NavigationLink {
                        ReadAloudSettingsView()
                    } label: {
                        LabeledContent("Read-Aloud", value: VoiceEngine.currentEngineName)
                    }
                } header: {
                    Text("Voice")
                } footer: {
                    Text("Which engine turns your voice into text, and which one reads it back. Apple's run on-device with no download; Whisper and Kokoro are optional and each fetch a one-time model.")
                }

                Section {
                    LabeledContent("Version", value: "1.0")
                } footer: {
                    Text("MindLocal keeps your journal on your device. Only weather forecasts and the optional Whisper model download use the network.")
                }
            }
            .albumScreen()
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
        deleteAll(MemoryGraphSnapshot.self)
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
