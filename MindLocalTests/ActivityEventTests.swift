import XCTest
@testable import MindLocal

final class ActivityEventTests: XCTestCase {

    private let day = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15))!

    // MARK: - ActivityTimeResolver

    func test_resolve_exactTime_combinesWithKnownDay_notNow() {
        let result = ActivityTimeResolver.resolve(timePhrase: "4pm", on: day)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: result.date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 16)
        XCTAssertFalse(result.isApproximate, "An exact stated time must not be flagged approximate")
    }

    func test_resolve_afternoon_mapsToRepresentativeHour_andIsApproximate() {
        let result = ActivityTimeResolver.resolve(timePhrase: "in the afternoon", on: day)
        let hour = Calendar.current.component(.hour, from: result.date)
        XCTAssertEqual(hour, 14)
        XCTAssertTrue(result.isApproximate)
    }

    func test_resolve_morning_mapsToRepresentativeHour() {
        let result = ActivityTimeResolver.resolve(timePhrase: "this morning", on: day)
        XCTAssertEqual(Calendar.current.component(.hour, from: result.date), 9)
        XCTAssertTrue(result.isApproximate)
    }

    func test_resolve_evening_mapsToRepresentativeHour() {
        let result = ActivityTimeResolver.resolve(timePhrase: "evening", on: day)
        XCTAssertEqual(Calendar.current.component(.hour, from: result.date), 18)
        XCTAssertTrue(result.isApproximate)
    }

    func test_resolve_emptyPhrase_fallsBackToNeutralHour_andIsApproximate() {
        let result = ActivityTimeResolver.resolve(timePhrase: "", on: day)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: result.date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 12)
        XCTAssertTrue(result.isApproximate)
    }

    // MARK: - ActivityEventDraft / ActivityEventCandidate

    func test_isActivityEvent_requiresBothTitleAndPerson() {
        XCTAssertTrue(ActivityEventDraft(title: "Coffee with David", with: "David", timePhrase: "4pm").isActivityEvent)
        XCTAssertFalse(ActivityEventDraft(title: "Went for a run", with: "", timePhrase: "").isActivityEvent,
            "A solo activity with no named person must not become an event candidate")
        XCTAssertFalse(ActivityEventDraft(title: "", with: "David", timePhrase: "4pm").isActivityEvent)
    }

    func test_candidates_dropsNonEventWorthyDrafts_andResolvesTimeForTheRest() {
        let drafts = [
            ActivityEventDraft(title: "Coffee with David", with: "David", timePhrase: "4 o'clock"),
            ActivityEventDraft(title: "Went for a run", with: "", timePhrase: ""),   // solo — dropped
            ActivityEventDraft(title: "Took Mom to her appointment", with: "Mom", timePhrase: "")
        ]
        let candidates = ActivityEventCandidate.candidates(from: drafts, day: day)

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].title, "Coffee with David")
        XCTAssertEqual(candidates[0].personName, "David")
        XCTAssertFalse(candidates[0].isApproximateTime)
        XCTAssertEqual(candidates[1].personName, "Mom")
        XCTAssertTrue(candidates[1].isApproximateTime, "No time stated should fall back to an approximate placement")
    }
}
