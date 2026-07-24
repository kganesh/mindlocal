import AppIntents
import SwiftData

/// "Hey Siri, log my day in MindLocal." Siri asks how the day went (listens),
/// extracts a structured journal entry on-device, saves it, and speaks a
/// confirmation (talks).
struct LogJournalEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Journal Entry"
    static var description = IntentDescription("Record how your day went in MindLocal.")

    // Runs without bringing the app forward, so Siri handles the whole exchange.
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Entry",
        requestValueDialog: "How was your day? Tell me what happened."
    )
    var note: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .result(dialog: "I didn't catch that, so nothing was saved.")
        }

        let context = SharedStore.container.mainContext

        // Structure it on-device if possible; otherwise save the raw note.
        let experience: Experience
        var appointmentCandidates: [AppointmentCandidate] = []
        if let draft = try? await ExtractionService().extractExperience(from: text), draft.isExperience {
            experience = draft.toExperience(rawText: text, occurredAt: .now)
            experience.decisions = draft.decisions
                .filter { $0.isDecision }
                .map { $0.toDecision(rawTranscript: text, occurredAt: .now) }
            appointmentCandidates = AppointmentCandidate.candidates(from: draft.appointments)
        } else {
            experience = Experience(title: String(text.prefix(48)), summary: text, rawText: text, occurredAt: .now)
        }

        context.insert(experience)
        PersonResolver.linkPeople(to: experience, in: context)
        EmbeddingService.embed(experience)
        try? context.save()

        let peopleWithReminders = Set(experience.reminders.compactMap(\.person?.id))
        if !peopleWithReminders.isEmpty {
            let events = (try? context.fetch(FetchDescriptor<Event>())) ?? []
            for person in experience.linkedPeople where peopleWithReminders.contains(person.id) {
                await EventReminderNotificationService.rescheduleAll(for: person, events: events)
            }
        }

        // No interactive review screen on this path, so a detected appointment
        // can only be surfaced as a notification, not an in-app "Add" card.
        for candidate in appointmentCandidates {
            await EventReminderNotificationService.promptToAddAppointment(candidate)
        }

        return .result(dialog: "Saved your journal for today.")
    }
}

struct MindLocalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogJournalEntryIntent(),
            phrases: [
                "Log my day in \(.applicationName)",
                "Add a journal entry in \(.applicationName)",
                "Journal with \(.applicationName)",
                "Record my day in \(.applicationName)"
            ],
            shortTitle: "Log Journal",
            systemImageName: "book"
        )
    }
}
