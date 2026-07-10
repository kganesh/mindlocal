import Foundation
import EventKit
import SwiftData

/// Reads the user's iPhone Calendar (EventKit) and imports upcoming events into
/// MindLocal's own Event store, so they appear on the timeline and get the same
/// weather-aware, grounded advice. Re-import upserts by EventKit identifier.
@MainActor
final class CalendarImportService {
    enum Result: Equatable {
        case denied
        case imported(new: Int, updated: Int)
    }

    private let store = EKEventStore()

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Imports events from now through `days` ahead. Returns counts, or `.denied`.
    func importUpcoming(days: Int = 30, into context: ModelContext) async -> Result {
        guard await requestAccess() else { return .denied }

        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: start) else {
            return .imported(new: 0, updated: 0)
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        let existing = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        var new = 0, updated = 0

        for ek in ekEvents {
            guard let identifier = ek.eventIdentifier else { continue }
            let title = (ek.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let date = ek.startDate else { continue }

            if let match = existing.first(where: { $0.externalId == identifier }) {
                match.title = title
                match.date = date
                if match.location.isEmpty, let loc = ek.location { match.location = loc }
                updated += 1
            } else {
                let event = Event(
                    title: title,
                    notes: ek.notes ?? "",
                    date: date,
                    location: ek.location ?? "",
                    externalId: identifier
                )
                context.insert(event)
                new += 1
            }
        }
        try? context.save()
        return .imported(new: new, updated: updated)
    }
}
