import XCTest
import SwiftData
@testable import MindLocal

@MainActor
final class BirthdayEventDeriverTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func test_nextOccurrence_laterThisYear_staysInThisYear() {
        let birthdate = date(1990, 8, 2)
        let now = date(2026, 7, 31)
        let next = BirthdayEventDeriver.nextOccurrence(of: birthdate, from: now, calendar: calendar)
        XCTAssertEqual(next, date(2026, 8, 2))
    }

    func test_nextOccurrence_alreadyPassedThisYear_rollsToNextYear() {
        let birthdate = date(1990, 1, 15)
        let now = date(2026, 7, 31)
        let next = BirthdayEventDeriver.nextOccurrence(of: birthdate, from: now, calendar: calendar)
        XCTAssertEqual(next, date(2027, 1, 15))
    }

    func test_nextOccurrence_isToday_countsAsUpcoming() {
        let birthdate = date(1990, 7, 31)
        let now = date(2026, 7, 31)
        let next = BirthdayEventDeriver.nextOccurrence(of: birthdate, from: now, calendar: calendar)
        XCTAssertEqual(next, date(2026, 7, 31))
    }

    /// Regression: a Feb 29 birthdate must not silently drift into March in a
    /// non-leap year — Calendar.date(from:) rolls an invalid Feb 29 forward.
    func test_nextOccurrence_feb29Birthdate_fallsBackToFeb28InNonLeapYear() {
        let birthdate = date(1992, 2, 29)   // 1992 was a leap year
        let now = date(2026, 1, 1)          // 2026 is not a leap year
        let next = BirthdayEventDeriver.nextOccurrence(of: birthdate, from: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: next!), 2,
            "Must stay in February, not roll into March")
        XCTAssertEqual(calendar.component(.day, from: next!), 28)
    }

    func test_nextOccurrence_feb29Birthdate_usesRealFeb29InLeapYear() {
        let birthdate = date(1992, 2, 29)
        let now = date(2028, 1, 1)          // 2028 is a leap year
        let next = BirthdayEventDeriver.nextOccurrence(of: birthdate, from: now, calendar: calendar)
        XCTAssertEqual(next, date(2028, 2, 29))
    }

    /// Regression: a birthday the user already entered by hand — with no
    /// particular relationship to BirthdayEventDeriver — must not get a
    /// second, duplicate event created alongside it.
    func test_ensureUpcomingEvents_skipsPersonWithEventAlreadyOnThatDay() async throws {
        let container = try ModelContainer(
            for: Person.self, Event.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let person = Person(name: "Akhil", birthdate: date(2015, 8, 2))
        context.insert(person)
        let existing = Event(title: "Akhil’s birthday", date: date(2026, 8, 2), person: person)
        context.insert(existing)
        try context.save()

        await BirthdayEventDeriver.ensureUpcomingEvents(in: context, now: date(2026, 7, 31))

        let allEvents = try context.fetch(FetchDescriptor<Event>())
        XCTAssertEqual(allEvents.count, 1, "Must not create a duplicate for a day that already has an event for this person")
    }

    func test_ensureUpcomingEvents_createsEventForPersonWithNoneScheduled() async throws {
        let container = try ModelContainer(
            for: Person.self, Event.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let person = Person(name: "Akhil", birthdate: date(2015, 8, 2))
        context.insert(person)
        try context.save()

        await BirthdayEventDeriver.ensureUpcomingEvents(in: context, now: date(2026, 7, 31))

        let allEvents = try context.fetch(FetchDescriptor<Event>())
        XCTAssertEqual(allEvents.count, 1)
        XCTAssertEqual(allEvents.first?.person?.id, person.id)
        XCTAssertTrue(allEvents.first?.isApproximateTime ?? false,
            "A derived birthday has no real time of day, so it must be flagged approximate")
        XCTAssertEqual(calendar.startOfDay(for: allEvents.first!.date), date(2026, 8, 2))
    }

    func test_ensureUpcomingEvents_ignoresPeopleWithNoBirthdate() async throws {
        let container = try ModelContainer(
            for: Person.self, Event.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(Person(name: "Sam"))
        try context.save()

        await BirthdayEventDeriver.ensureUpcomingEvents(in: context, now: date(2026, 7, 31))

        XCTAssertEqual(try context.fetch(FetchDescriptor<Event>()).count, 0)
    }
}
