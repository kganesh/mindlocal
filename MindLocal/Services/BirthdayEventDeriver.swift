import Foundation
import SwiftData

/// Ensures every person with a recorded birthdate has an upcoming birthday
/// `Event` on the calendar — run once per launch (alongside the memory graph
/// rebuild) so a birthday never needs to be re-entered by hand each year the
/// way a normal one-off Event would.
@MainActor
enum BirthdayEventDeriver {
    static func ensureUpcomingEvents(in context: ModelContext, now: Date = .now) async {
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        guard people.contains(where: { $0.birthdate != nil }) else { return }
        let events = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        let calendar = Calendar.current

        for person in people {
            guard let birthdate = person.birthdate,
                  let nextOccurrence = nextOccurrence(of: birthdate, from: now, calendar: calendar)
            else { continue }

            // Matches on person + exact day regardless of title or who created
            // it — a birthday the user already entered by hand (or one derived
            // last year that hasn't rolled over yet) must not get a duplicate.
            let alreadyScheduled = events.contains { event in
                event.person?.id == person.id && calendar.isDate(event.date, inSameDayAs: nextOccurrence)
            }
            guard !alreadyScheduled else { continue }

            let event = Event(
                title: "\(person.name)’s birthday",
                date: nextOccurrence,
                isApproximateTime: true,
                domain: .other,
                person: person
            )
            context.insert(event)
            EmbeddingService.embed(event)
            await EventReminderNotificationService.rescheduleAll(for: person, events: [event])
        }
    }

    /// The next calendar date (today or later) matching `birthdate`'s month/day.
    /// The year on `birthdate` itself is never used — only month/day recur.
    /// A Feb 29 birthdate falls back to Feb 28 in non-leap years, since what
    /// matters is that an occurrence exists every year, not which exact day.
    static func nextOccurrence(of birthdate: Date, from now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        let birthComponents = calendar.dateComponents([.month, .day], from: birthdate)
        guard let month = birthComponents.month, let day = birthComponents.day else { return nil }
        let thisYear = calendar.component(.year, from: today)

        for year in [thisYear, thisYear + 1] {
            var components = DateComponents(year: year, month: month, day: day)
            guard let candidate = calendar.date(from: components) else { continue }
            // An invalid Feb 29 rolls forward into March — pull it back to
            // Feb 28 instead of letting the occurrence silently drift a month.
            let normalized: Date
            if calendar.component(.month, from: candidate) == month {
                normalized = candidate
            } else {
                components.day = 28
                normalized = calendar.date(from: components) ?? candidate
            }
            if normalized >= today {
                return normalized
            }
        }
        return nil
    }
}
