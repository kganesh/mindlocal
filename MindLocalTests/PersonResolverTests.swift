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

    func test_resolve_kinshipAssignment_createsRelationshipEdgeToMe() {
        let ctx = makeContext()
        let me = Person(name: "Me", isMe: true)
        ctx.insert(me)

        _ = PersonResolver.resolve(["my sister"], assignments: ["my sister": "Emma"], in: ctx)

        let edges = (try? ctx.fetch(FetchDescriptor<PersonRelationship>())) ?? []
        XCTAssertEqual(edges.count, 1)
        let edge = edges[0]
        XCTAssertEqual(edge.type, .sibling)
        XCTAssertTrue(edge.subject?.name == "Emma" && edge.object?.isMe == true)

        // A later mention of "sister" now resolves via the graph (no duplicate edge).
        _ = PersonResolver.resolve(["sister"], in: ctx)
        let after = (try? ctx.fetch(FetchDescriptor<PersonRelationship>())) ?? []
        XCTAssertEqual(after.count, 1)
    }

    func test_kinshipRole_mapsMentions() {
        XCTAssertEqual(PersonResolver.kinshipRole(for: "my sister"), .sibling)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "mom"), .parent)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "my son"), .child)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "wife"), .spouse)
        XCTAssertNil(PersonResolver.kinshipRole(for: "my manager"))
    }

    func test_kinshipRole_extendedRelations() {
        XCTAssertEqual(PersonResolver.kinshipRole(for: "my uncle"), .auntUncle)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "aunt"), .auntUncle)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "my niece"), .nieceNephew)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "nephew"), .nieceNephew)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "my cousin"), .cousin)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "grandma"), .grandparent)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "my grandson"), .grandchild)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "my physician"), .physician)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "my doctor"), .physician)
    }

    func test_kinshipRole_inLaws_notMisMappedToParentOrSibling() {
        XCTAssertEqual(PersonResolver.kinshipRole(for: "my mother-in-law"), .parentInLaw)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "father in law"), .parentInLaw)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "my brother-in-law"), .siblingInLaw)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "sister in law"), .siblingInLaw)
        XCTAssertEqual(PersonResolver.kinshipRole(for: "my son-in-law"), .childInLaw)
    }

    func test_resolve_inLawAssignment_createsRelationshipEdgeToMe() {
        let ctx = makeContext()
        let me = Person(name: "Me", isMe: true)
        ctx.insert(me)

        _ = PersonResolver.resolve(["my mother-in-law"], assignments: ["my mother-in-law": "Carol"], in: ctx)

        let edges = (try? ctx.fetch(FetchDescriptor<PersonRelationship>())) ?? []
        XCTAssertEqual(edges.count, 1)
        XCTAssertEqual(edges.first?.type, .parentInLaw)
        XCTAssertTrue(edges.first?.subject?.name == "Carol" && edges.first?.object?.isMe == true)
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
