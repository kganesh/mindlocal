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
            ("the writer", false), ("the narrator", false), ("the author", false),
            ("kids", false), ("children", false), ("the kids", false), ("his kids", false),
            ("parents", false), ("cousins", false), ("grandkids", false),
            // Real single names ending in "s" are still people.
            ("James", true), ("Chris", true), ("Charles", true),
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

    // MARK: - isKinshipTerm (bulk table)

    func test_isKinshipTerm_bulk() {
        let cases: [(String, Bool)] = [
            ("mom", true), ("my sister", true), ("brother", true), ("wife", true),
            ("grandma", true), ("mother-in-law", true), ("my brother-in-law", true),
            ("uncle", true), ("son", true),
            ("Sam", false), ("Priya", false), ("my manager", false),
            ("the recruiter", false), ("kids", false),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(PersonResolver.isKinshipTerm(input), expected, "isKinshipTerm(\(input))")
        }
    }

    func test_resolve_kinshipTerm_skippedThenAssignedThenAutoResolves() {
        let ctx = makeContext()
        // First appearance, no assignment → asked-about, so skipped (not created).
        let first = PersonResolver.resolve(["my sister"], in: ctx)
        XCTAssertTrue(first.isEmpty)

        // User identifies "my sister" as Emma.
        let assigned = PersonResolver.resolve(["my sister"], assignments: ["my sister": "Emma"], in: ctx)
        XCTAssertEqual(assigned.map(\.name), ["Emma"])
        XCTAssertTrue(assigned.first?.aliases.contains("my sister") ?? false)

        // Later entries auto-resolve "my sister" → Emma via the alias.
        let later = PersonResolver.resolve(["my sister"], in: ctx)
        XCTAssertEqual(later.map(\.name), ["Emma"])
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
