import XCTest
import SwiftData
@testable import MindLocal

@MainActor
final class PersonResolverTests: XCTestCase {

    /// Reuse the single (in-memory under test) app container, wiped per test.
    private func makeContext() -> ModelContext {
        let ctx = SharedStore.container.mainContext
        for p in (try? ctx.fetch(FetchDescriptor<Person>())) ?? [] { ctx.delete(p) }
        for r in (try? ctx.fetch(FetchDescriptor<PersonRelationship>())) ?? [] { ctx.delete(r) }
        try? ctx.save()
        return ctx
    }

    // MARK: - isLikelyPerson (bulk table)

    func test_isLikelyPerson_bulk() {
        let cases: [(String, Bool)] = [
            ("Sam", true), ("John Smith", true), ("Priya", true), ("Chris", true),
            ("mom", true), ("my manager", true), ("Dr. Patel", true),
            ("senior engineers", false), ("team members", false), ("other senior engineers", false),
            ("colleagues", false), ("the team", false), ("everyone", false),
            ("self", false), ("me", false), ("myself", false), ("people", false),
            ("", false), ("   ", false),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(PersonResolver.isLikelyPerson(input), expected, "isLikelyPerson(\(input))")
        }
    }

    // MARK: - isRoleReference (bulk table)

    func test_isRoleReference_bulk() {
        let cases: [(String, Bool)] = [
            ("my manager", true), ("principal engineer", true), ("the recruiter", true),
            ("staff engineer", true), ("my boss", true), ("a senior developer", true),
            ("Sam", false), ("Lilly", false), ("mom", false), ("my sister", false),
            ("John Smith", false), ("Priya", false),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(PersonResolver.isRoleReference(input), expected, "isRoleReference(\(input))")
        }
    }

    // MARK: - resolve

    func test_resolve_createsProperNames_skipsPluralsAndRoles() {
        let ctx = makeContext()
        let people = PersonResolver.resolve(["Sam", "senior engineers", "my manager"], in: ctx)
        // Sam created; plural skipped; unassigned role skipped.
        XCTAssertEqual(people.map(\.name), ["Sam"])
    }

    func test_resolve_dedupesWithinBatch() {
        let ctx = makeContext()
        let people = PersonResolver.resolve(["Sam", "sam", "Sam "], in: ctx)
        XCTAssertEqual(people.count, 1)
    }

    func test_resolve_roleAssignment_linksAndAddsAlias_thenAutoResolves() {
        let ctx = makeContext()
        // First entry: "my manager" identified as Alex.
        let first = PersonResolver.resolve(["my manager"], assignments: ["my manager": "Alex"], in: ctx)
        XCTAssertEqual(first.map(\.name), ["Alex"])
        XCTAssertTrue(first.first?.aliases.contains("my manager") ?? false)

        // Later entry: "my manager" now auto-resolves to Alex via the alias.
        let second = PersonResolver.resolve(["my manager"], in: ctx)
        XCTAssertEqual(second.map(\.name), ["Alex"])
    }

    func test_resolve_emptyAssignmentSkips() {
        let ctx = makeContext()
        let people = PersonResolver.resolve(["my manager"], assignments: ["my manager": ""], in: ctx)
        XCTAssertTrue(people.isEmpty)
    }

    func test_resolve_relativeTerm_viaGraph() {
        let ctx = makeContext()
        let me = Person(name: "Me", isMe: true)
        let lilly = Person(name: "Lilly")
        ctx.insert(me); ctx.insert(lilly)
        ctx.insert(PersonRelationship(subject: lilly, type: .spouse, object: me))

        let people = PersonResolver.resolve(["wife"], in: ctx)
        XCTAssertEqual(people.map(\.name), ["Lilly"])
    }
}
