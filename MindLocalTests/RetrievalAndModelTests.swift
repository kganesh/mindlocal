import XCTest
@testable import MindLocal

final class RetrievalAndModelTests: XCTestCase {

    // MARK: - Decision → outcome revisit loop (Phase 1)

    func test_revisitDelay_byStakes() {
        XCTAssertEqual(Decision.revisitDelay(for: .high),   30 * 86_400)
        XCTAssertEqual(Decision.revisitDelay(for: .medium), 14 * 86_400)
        XCTAssertNil(Decision.revisitDelay(for: .low))
    }

    func test_revisitDate_offsetsFromOccurrence() {
        let made = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Decision.revisitDate(for: .high, occurredAt: made),
                       made.addingTimeInterval(30 * 86_400))
        XCTAssertNil(Decision.revisitDate(for: .low, occurredAt: made))
    }

    @MainActor
    func test_isDueForRevisit_dependsOnDateAndOutcome() {
        let now = Date()
        let due = Decision(title: "t", statement: "s", stakes: .high,
                           revisitAt: now.addingTimeInterval(-86_400))   // yesterday
        XCTAssertTrue(due.isDueForRevisit(asOf: now))

        let notYet = Decision(title: "t", statement: "s", stakes: .high,
                              revisitAt: now.addingTimeInterval(86_400))  // tomorrow
        XCTAssertFalse(notYet.isDueForRevisit(asOf: now))

        let unscheduled = Decision(title: "t", statement: "s", stakes: .low)
        XCTAssertFalse(unscheduled.isDueForRevisit(asOf: now))

        due.outcome = Outcome(result: .workedOut)   // recorded → no longer due
        XCTAssertFalse(due.isDueForRevisit(asOf: now))
    }

    // MARK: - Decision insights (you-model aggregates, Phase 2)

    @MainActor
    private func decision(_ domain: Domain, values: [String], _ result: OutcomeResult?) -> Decision {
        let d = Decision(title: "t", statement: "s", valuesPrioritized: values, domain: domain, stakes: .medium)
        if let result { d.outcome = Outcome(result: result) }
        return d
    }

    @MainActor
    func test_decisionInsights_ignoresDecisionsWithoutOutcome() {
        let decisions = [
            decision(.money, values: ["safety"], .workedOut),
            decision(.money, values: ["safety"], nil),          // no outcome → ignored
        ]
        let overall = DecisionInsights.overall(decisions)
        XCTAssertEqual(overall.total, 1)
        XCTAssertEqual(overall.workedOut, 1)
    }

    @MainActor
    func test_decisionInsights_byDomain_andRate() {
        let decisions = [
            decision(.money, values: [], .workedOut),
            decision(.money, values: [], .regret),
            decision(.health, values: [], .workedOut),
        ]
        let groups = DecisionInsights.byDomain(decisions)
        XCTAssertEqual(groups.first?.name, "Money")          // most decisions first
        let money = groups.first { $0.name == "Money" }!
        XCTAssertEqual(money.tally.decided, 2)
        XCTAssertEqual(money.tally.workedOutRate, 0.5)
    }

    @MainActor
    func test_decisionInsights_byValue_groupsCaseInsensitively() {
        let decisions = [
            decision(.other, values: ["Family time"], .workedOut),
            decision(.other, values: ["family time"], .regret),
            decision(.other, values: ["growth"], .workedOut),
        ]
        let groups = DecisionInsights.byPrioritizedValue(decisions)
        let family = groups.first { $0.name.lowercased() == "family time" }!
        XCTAssertEqual(family.tally.total, 2)                 // merged across casing
        XCTAssertEqual(family.tally.workedOut, 1)
        XCTAssertEqual(family.tally.regret, 1)
    }

    @MainActor
    func test_tally_tooEarlyExcludedFromRate() {
        var t = DecisionInsights.Tally()
        t.add(.workedOut); t.add(.tooEarly)
        XCTAssertEqual(t.total, 2)
        XCTAssertEqual(t.decided, 1)
        XCTAssertEqual(t.workedOutRate, 1.0)   // too-early doesn't dilute the rate
    }

    // MARK: - Decision history retriever ("your history on this", Phase 3)

    @MainActor
    private func made(_ domain: Domain, prioritized: [String] = [], tradedOff: [String] = [],
                      title: String = "d", _ result: OutcomeResult?) -> Decision {
        let d = Decision(title: title, statement: "s", valuesPrioritized: prioritized,
                         valuesTradedOff: tradedOff, domain: domain)
        if let result { d.outcome = Outcome(result: result) }
        return d
    }

    @MainActor
    func test_history_onlyReturnsOutcomedAndScopedDecisions() {
        let past = [
            made(.money, tradedOff: ["safety"], title: "crypto", .regret),   // relevant + outcome
            made(.money, tradedOff: ["safety"], title: "no-outcome", nil),   // no outcome → excluded
            made(.health, title: "unrelated", .workedOut),                   // different domain, no value overlap
        ]
        let result = DecisionHistoryRetriever.history(
            domain: .money, prioritized: [], tradedOff: ["safety"], among: past
        )
        XCTAssertEqual(result.matches.map { $0.decision.title }, ["crypto"])
    }

    @MainActor
    func test_history_rankSharedValueOverDomainOnly() {
        let valueMatch  = made(.money, tradedOff: ["safety"], title: "value", .regret)
        let domainOnly  = made(.money, title: "domainonly", .workedOut)
        let result = DecisionHistoryRetriever.history(
            domain: .money, prioritized: [], tradedOff: ["safety"],
            among: [domainOnly, valueMatch]
        )
        XCTAssertEqual(result.matches.first?.decision.title, "value")
    }

    @MainActor
    func test_history_patternLine_reportsWorkedOutRatio() {
        let past = [
            made(.money, tradedOff: ["safety"], .regret),
            made(.money, tradedOff: ["safety"], .workedOut),
            made(.money, tradedOff: ["safety"], .regret),
        ]
        let result = DecisionHistoryRetriever.history(
            domain: .money, prioritized: [], tradedOff: ["safety"], among: past
        )
        XCTAssertEqual(result.pattern, "Your decisions that traded off safety worked out 1 of 3.")
    }

    @MainActor
    func test_history_emptyWhenNoRelevantHistory() {
        let result = DecisionHistoryRetriever.history(
            domain: .money, prioritized: ["growth"], tradedOff: [],
            among: [made(.health, title: "x", .workedOut)]
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Cosine (deterministic)

    func test_cosine_identicalAndOrthogonal() {
        XCTAssertEqual(EmbeddingService.cosine([1, 0, 0], [1, 0, 0]), 1, accuracy: 0.0001)
        XCTAssertEqual(EmbeddingService.cosine([1, 0, 0], [0, 1, 0]), 0, accuracy: 0.0001)
        XCTAssertEqual(EmbeddingService.cosine([1, 2, 3], [2, 4, 6]), 1, accuracy: 0.0001) // same direction
        XCTAssertEqual(EmbeddingService.cosine([], []), 0)
    }

    // MARK: - Semantic ranking (NLEmbedding, available on the simulator)

    private struct Item { let text: String }

    func test_semanticRetriever_ranksRelevantHigher() {
        let items = [
            Item(text: "went for a morning run along the river and felt great"),
            Item(text: "reviewed the quarterly budget with the finance team"),
            Item(text: "called my mom for her birthday"),
        ]
        let top = SemanticRetriever.topK(
            items, query: "exercise and fitness", k: 1,
            text: { $0.text }, embedding: { _ in [] }
        )
        // If embeddings are available, the running entry should win; otherwise the
        // fallback returns the first item (still the running entry here).
        XCTAssertEqual(top.first?.text, items[0].text)
    }

    func test_semanticRetriever_respectsK() {
        let items = (0..<20).map { Item(text: "entry number \($0)") }
        let top = SemanticRetriever.topK(items, query: "anything", k: 5,
                                         text: { $0.text }, embedding: { _ in [] })
        XCTAssertEqual(top.count, 5)
    }

    // MARK: - Mood scoring

    func test_toneScore() {
        XCTAssertEqual(ExperienceTone.pleasant.score, 1, accuracy: 0.0001)
        XCTAssertEqual(ExperienceTone.mixed.score, 0, accuracy: 0.0001)
        XCTAssertEqual(ExperienceTone.unpleasant.score, -1, accuracy: 0.0001)
    }

    // MARK: - Prompt building

    func test_advisorPrompt_includesQuestionAndContext() {
        let prompt = Prompts.advisorPrompt(question: "How do I handle stress?", context: "PAST: went running")
        XCTAssertTrue(prompt.contains("How do I handle stress?"))
        XCTAssertTrue(prompt.contains("went running"))
    }

    func test_eventAdvisorPrompt_includesWeatherWhenOutdoor() {
        let withWeather = Prompts.eventAdvisorPrompt(event: "Picnic", when: "Sat", weather: "Sunny, 20C", context: "ctx")
        XCTAssertTrue(withWeather.contains("Sunny, 20C"))
        let without = Prompts.eventAdvisorPrompt(event: "Meeting", when: "Mon", weather: nil, context: "ctx")
        XCTAssertFalse(without.lowercased().contains("weather forecast"))
    }

    // MARK: - Memory graph retrieval and packing

    /// Regression: "Aditya is Child of Ganesh Kolekar (this is you, the diary's
    /// author)." was intermittently misread by the model as "Aditya is the
    /// diary's author" — the trailing parenthetical, embedded inside another
    /// person's relationship sentence, is ambiguous about which name it
    /// modifies. Verify the profile now reads unambiguously ("your child") and
    /// never emits the "(this is you...)" tag inside someone else's line.
    @MainActor
    func test_personContextBuilder_profile_relationshipToMe_readsUnambiguously() {
        let me = Person(name: "Ganesh", lastName: "Kolekar", isMe: true)
        let aditya = Person(name: "Aditya", lastName: "Kolekar")
        let relationship = PersonRelationship(subject: aditya, type: .child, object: me)

        let profile = PersonContextBuilder.profile(for: aditya, relationships: [relationship])

        XCTAssertTrue(profile.contains("Aditya is your child."),
            "Should state the relationship to Me directly and unambiguously")
        XCTAssertFalse(profile.contains("this is you"),
            "Must never embed the ambiguous author tag inside another person's relationship line")
    }

    /// Regression: "Who is Ganesh" (Ganesh being Me) returned wildly inconsistent
    /// answers across repeated identical questions — sometimes correct ("Ganesh
    /// is you... You are a Spouse of Gayatri"), sometimes self-contradictory
    /// ("Ganesh is your spouse", as if married to himself). Root cause: the
    /// profile header said "(this is you...)" but every relationship line
    /// beneath it was still third person ("Ganesh is Spouse of Gayatri"),
    /// mixing second- and third-person framing within one profile and letting
    /// the model's identity resolution vary by sampling run. Verify Ganesh's
    /// own profile stays in second person throughout.
    @MainActor
    func test_personContextBuilder_profile_forMeAnchor_staysSecondPersonThroughout() {
        let me = Person(name: "Ganesh", lastName: "Kolekar", isMe: true)
        let spouse = Person(name: "Gayatri", lastName: "Kolekar")
        let relationship = PersonRelationship(subject: me, type: .spouse, object: spouse)

        let profile = PersonContextBuilder.profile(for: me, relationships: [relationship])

        XCTAssertTrue(profile.contains("You are Spouse of Gayatri Kolekar."),
            "Ganesh's own profile must phrase his relationships in second person, matching the header's 'this is you' tag")
        XCTAssertFalse(profile.contains("Ganesh is Spouse"),
            "Must never mix third-person relationship lines into the reader's own profile")
    }

    /// Regression: "What should be the priorities for Akhil's birthday?"
    /// produced a hallucinated date ("July 28th, 2027") by conflating Akhil's
    /// actual birthday event with a different, similarly-worded birthday event
    /// for someone else nearby in the same Evidence list. Since Person.birthdate
    /// already exists, the profile should state the real upcoming birthday as a
    /// computed fact instead of leaving the model to find it in Evidence.
    @MainActor
    func test_personContextBuilder_profile_includesComputedUpcomingBirthday() {
        let calendar = Calendar(identifier: .gregorian)
        let birthdate = calendar.date(from: DateComponents(year: 2015, month: 8, day: 2))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31))!
        let akhil = Person(name: "Akhil", lastName: "Kolekar", birthdate: birthdate)

        let profile = PersonContextBuilder.profile(for: akhil, relationships: [], now: now)

        XCTAssertTrue(profile.contains("Upcoming birthday"),
            "A person with a recorded birthdate should have their upcoming birthday stated as a computed fact")
        XCTAssertTrue(profile.contains("August 2, 2026"),
            "The stated date must be the real next occurrence, not something the model has to derive")
    }

    func test_personContextBuilder_profile_omitsBirthdayLineWhenNoneRecorded() {
        let sam = Person(name: "Sam")
        let profile = PersonContextBuilder.profile(for: sam, relationships: [])
        XCTAssertFalse(profile.contains("Upcoming birthday"))
    }

    func test_personContextBuilder_profile_includesOccupationLikesAndDislikes() {
        let akhil = Person(
            name: "Akhil", occupation: "Student",
            likes: ["chocolate ice cream cake", "hiking"], dislikes: ["cilantro"]
        )
        let profile = PersonContextBuilder.profile(for: akhil, relationships: [])

        XCTAssertTrue(profile.contains("Occupation: Student."))
        XCTAssertTrue(profile.contains("Likes: chocolate ice cream cake, hiking."))
        XCTAssertTrue(profile.contains("Dislikes: cilantro."))
    }

    func test_personContextBuilder_profile_omitsPreferenceLinesWhenNoneRecorded() {
        let sam = Person(name: "Sam")
        let profile = PersonContextBuilder.profile(for: sam, relationships: [])
        XCTAssertFalse(profile.contains("Occupation"))
        XCTAssertFalse(profile.contains("Likes"))
        XCTAssertFalse(profile.contains("Dislikes"))
    }

    @MainActor
    func test_memoryQueryResolver_resolvesRelationshipPhraseThroughPeopleGraph() {
        let me = Person(name: "Me", isMe: true)
        let spouse = Person(name: "Lilly")
        let relationship = PersonRelationship(subject: spouse, type: .spouse, object: me)

        let intent = MemoryQueryResolver.resolve(
            query: "What should I ask my wife before dinner?",
            people: [me, spouse],
            relationships: [relationship]
        )

        XCTAssertEqual(intent.mentionedPeople.first?.personID, spouse.id)
        XCTAssertEqual(intent.mentionedPeople.first?.matchKind, .relationship)
        XCTAssertTrue(intent.wantsReminders)
    }

    func test_memoryQueryResolver_detectsMostRecentInteractionPhrasing() {
        let intent = MemoryQueryResolver.resolve(
            query: "Who is Aditya and when did I meet him last time?",
            people: [], relationships: []
        )
        XCTAssertTrue(intent.wantsMostRecentInteraction)
    }

    func test_memoryQueryResolver_plainQuestion_doesNotFlagMostRecentInteraction() {
        let intent = MemoryQueryResolver.resolve(
            query: "Who is Aditya?",
            people: [], relationships: []
        )
        XCTAssertFalse(intent.wantsMostRecentInteraction)
    }

    /// Reproduces the exact on-device scenario reported: Alex's own People
    /// page correctly shows the conflict AND the "Argument with Alex about
    /// Project Deadline" entry (proving conflict.withPerson and
    /// experience.linkedPeople ARE both correctly resolved to this Alex —
    /// not a stale-link problem), yet "How to resolve conflict with Alex"
    /// still retrieved none of it. Builds the graph from properly-linked
    /// records exactly like this and checks whether the conflict/entry ever
    /// reach evidenceNodes for that query, to isolate whether the defect is
    /// in retrieval/scoring rather than in person-resolution.
    @MainActor
    func test_memoryGraphRetriever_conflict_properlyLinkedConflict_stillReachesEvidence() {
        let me = Person(name: "Ganesh", lastName: "Kolekar", isMe: true)
        let alex = Person(name: "Alex", occupation: "Software engineer")
        let coworker = PersonRelationship(subject: alex, type: .coworker, object: me)

        let conflict = Conflict(
            summary: "disagreement about project deadline",
            personName: "Alex",
            feelings: "frustrated",
            resolution: .unresolved
        )
        conflict.withPerson = alex

        let experience = Experience(
            title: "Argument with Alex about Project Deadline",
            summary: "Had a rough evening. Alex and I got into an argument about the project deadline.",
            tone: .unpleasant,
            domain: .work,
            people: ["Alex"]
        )
        experience.linkedPeople = [alex]
        experience.conflicts = [conflict]

        let graph = MemoryGraphBuilder.build(
            experiences: [experience], events: [], decisions: [],
            people: [me, alex], relationships: [coworker],
            conflicts: [], reminders: []
        )

        let result = MemoryGraphRetriever.retrieve(
            query: "How to resolve conflict with Alex",
            graph: graph, people: [me, alex], relationships: [coworker], limit: 24
        )

        XCTAssertTrue(result.evidenceNodes.contains { $0.title.contains("Argument with Alex") },
            "The properly-linked conflict entry must reach evidence for a question naming both 'conflict' and 'Alex'")
    }

    /// Regression: the retriever correctly ranks the Alex conflict entry
    /// highly (previous test), but `MemoryGraphContextPacker.pack` then
    /// RE-SORTED evidence purely by node kind + date, discarding that
    /// relevance ranking entirely — so once several newer, unrelated
    /// "productive day" entries exist (exactly like the real journal), an
    /// older-but-highly-relevant conflict entry gets pushed past `maxNodes`
    /// and silently dropped from what the model actually sees, even though
    /// the retriever scored it as the most relevant thing in the graph.
    /// Dates are relative to `now` (not fixed epoch constants) so
    /// `isRecentEvidence`'s 30-day window — the thing that puts the
    /// unrelated entries in real competition for a slot in the first
    /// place — behaves the same regardless of when this test runs.
    @MainActor
    func test_memoryGraphContextPacker_selectsByRelevance_beforeSortingForDisplay() {
        let now = Date()
        let me = Person(name: "Ganesh", lastName: "Kolekar", isMe: true)
        let alex = Person(name: "Alex", occupation: "Software engineer")
        let coworker = PersonRelationship(subject: alex, type: .coworker, object: me)

        let conflict = Conflict(
            summary: "disagreement about project deadline",
            personName: "Alex", feelings: "frustrated", resolution: .unresolved
        )
        conflict.withPerson = alex
        let argument = Experience(
            id: UUID(), createdAt: now.addingTimeInterval(-14 * 86_400),   // 14 days ago
            title: "Argument with Alex about Project Deadline",
            summary: "Had a rough evening. Alex and I got into an argument about the project deadline.",
            tone: .unpleasant, domain: .work, people: ["Alex"]
        )
        argument.linkedPeople = [alex]
        argument.conflicts = [conflict]

        // Several newer, unrelated entries — same shape as the real journal
        // (dated after the argument, no connection to Alex at all).
        let unrelated = (0..<5).map { i in
            Experience(
                id: UUID(), createdAt: now.addingTimeInterval(-Double(i + 1) * 86_400),   // 1-5 days ago
                title: "Productive Day \(i)",
                summary: "Worked from home on personal projects.",
                tone: .pleasant, domain: .work
            )
        }

        let graph = MemoryGraphBuilder.build(
            experiences: [argument] + unrelated, events: [], decisions: [],
            people: [me, alex], relationships: [coworker],
            conflicts: [], reminders: []
        )

        let result = MemoryGraphRetriever.retrieve(
            query: "How to resolve conflict with Alex",
            graph: graph, people: [me, alex], relationships: [coworker], now: now, limit: 24
        )
        let packed = MemoryGraphContextPacker.pack(result, maxNodes: 5, maxEdges: 12)

        // Checks the Evidence block specifically — "Argument with Alex" also
        // appears in "Useful links" edge labels regardless of this bug, so a
        // bare packed.contains(...) would false-pass even when Evidence itself
        // dropped it entirely.
        let evidenceBlock = packed.components(separatedBy: "\n\n").first { $0.hasPrefix("Evidence:") } ?? ""
        XCTAssertTrue(evidenceBlock.contains("Had a rough evening"),
            "The retriever's top-ranked evidence must survive packing into the Evidence block, even when it's older than several unrelated, lower-relevance entries")
    }

    /// Regression, second layer: even after evidence is SELECTED by
    /// relevance, the packer used to re-sort the selected items by kind then
    /// date for display (event > entry > conflict) — so a completely
    /// unrelated event ("Wisdom tooth extraction") landed ahead of the
    /// actually-relevant conflict entry in the composed string purely
    /// because "event" outranks "entry"/"conflict" by kind. That's exactly
    /// backwards once AdviceService's real 1200-char budget has to truncate:
    /// it cuts from the end, so whatever the kind/date sort pushed later —
    /// even the most relevant item — is the first thing silently dropped.
    /// Runs the full pipeline (retrieve -> pack -> AdviceService.context)
    /// with the app's real character budget to prove the fix holds
    /// end-to-end, not just inside the packer in isolation.
    @MainActor
    func test_advisorContext_relevantOlderEvidence_survivesRealBudget_despiteUnrelatedEvent() {
        let now = Date()
        let me = Person(name: "Ganesh", lastName: "Kolekar", isMe: true)
        let alex = Person(name: "Alex", occupation: "Software engineer")
        let coworker = PersonRelationship(subject: alex, type: .coworker, object: me)

        let conflict = Conflict(
            summary: "disagreement about project deadline",
            personName: "Alex", feelings: "frustrated", resolution: .unresolved
        )
        conflict.withPerson = alex
        let argument = Experience(
            id: UUID(), createdAt: now.addingTimeInterval(-14 * 86_400),
            title: "Argument with Alex about Project Deadline",
            summary: "Had a rough evening. Alex and I got into an argument about the project deadline.",
            tone: .unpleasant, domain: .work, people: ["Alex"]
        )
        argument.linkedPeople = [alex]
        argument.conflicts = [conflict]

        let unrelatedEvent = Event(title: "Wisdom tooth extraction", date: now.addingTimeInterval(-3 * 86_400), domain: .other)
        let unrelated = (0..<4).map { i in
            Experience(
                id: UUID(), createdAt: now.addingTimeInterval(-Double(i + 1) * 86_400),
                title: "Productive Day \(i)",
                summary: "Worked from home on personal projects and technical prep. Had breakfast and lunch.",
                tone: .pleasant, domain: .work
            )
        }

        let graph = MemoryGraphBuilder.build(
            experiences: [argument] + unrelated, events: [unrelatedEvent], decisions: [],
            people: [me, alex], relationships: [coworker],
            conflicts: [], reminders: []
        )
        let result = MemoryGraphRetriever.retrieve(
            query: "How to resolve conflict with Alex",
            graph: graph, people: [me, alex], relationships: [coworker], now: now, limit: 24
        )
        let packed = MemoryGraphContextPacker.pack(result)
        let people = [PersonProfileSummary(id: alex.id, text: "Alex:\n  Occupation: Software engineer.\n  Alex is your coworker.")]

        let context = AdviceService.context(
            decisions: [], experiences: [], people: people, graphContext: packed
        )

        XCTAssertTrue(context.contains("Argument with Alex"),
            "The most relevant evidence must survive the real character budget, even with an unrelated event and several unrelated entries also present")
    }

    /// Regression: "how to resolve conflict with Alex" produced generic,
    /// ungrounded boilerplate — the actual "Argument with Alex about Project
    /// Deadline" conflict entry never showed up in retrieved evidence at all.
    /// Root cause: `conflict.withPerson` was never resolved to the real Alex
    /// `Person` (a stale link, or one that predates person-resolution ever
    /// running for that entry), so the graph attached it to a permanently
    /// separate "unresolved conflict person" node instead — invisible to the
    /// boost a mentioned person's real connections get. The graph rebuilds
    /// from scratch every time, so it should self-heal via a live name match
    /// against the current People list rather than trusting a stale link.
    @MainActor
    func test_memoryGraphBuilder_conflict_selfHealsPersonLinkViaLiveNameMatch() {
        let alex = Person(name: "Alex")
        let conflict = Conflict(summary: "Argument about deadline", personName: "Alex")
        // withPerson intentionally left nil, simulating a link that was never
        // (or is no longer) resolved.

        let graph = MemoryGraphBuilder.build(
            experiences: [], events: [], decisions: [],
            people: [alex], relationships: [],
            conflicts: [conflict], reminders: []
        )

        let alexID = MemoryGraphBuilder.personNodeID(alex)
        XCTAssertTrue(graph.edges.contains { $0.kind == .withPerson && $0.to == alexID },
            "A conflict with an unresolved withPerson must still connect to a Person that matches its personName by live lookup")
        XCTAssertFalse(graph.nodes.contains { $0.summary == "Unresolved conflict person" },
            "Must not fall back to an orphaned 'unresolved' node when a real Person already matches by name")
    }

    @MainActor
    func test_memoryGraphBuilder_reminder_selfHealsPersonLinkViaLiveNameMatch() {
        let alex = Person(name: "Alex")
        let reminder = Reminder(text: "Ask about the deadline plan", personName: "Alex")

        let graph = MemoryGraphBuilder.build(
            experiences: [], events: [], decisions: [],
            people: [alex], relationships: [],
            conflicts: [], reminders: [reminder]
        )

        let alexID = MemoryGraphBuilder.personNodeID(alex)
        XCTAssertTrue(graph.edges.contains { $0.kind == .aboutPerson && $0.to == alexID },
            "A reminder with an unresolved person must still connect to a Person that matches its personName by live lookup")
        XCTAssertFalse(graph.nodes.contains { $0.summary == "Unresolved reminder person" },
            "Must not fall back to an orphaned 'unresolved' node when a real Person already matches by name")
    }

    /// Regression: "when did I last meet Aditya" returned an OLDER entry (July
    /// 18, shopping at Costco) instead of a more recent one (July 22, dinner at
    /// home) — both were present in context, but the on-device model picked the
    /// wrong one when left to scan dated text itself. mostRecentInteraction
    /// computes the real max by date over every node directly linked to the
    /// person, independent of the general relevance-score ranking (which is
    /// exactly what let the wrong node surface as more "relevant" before).
    @MainActor
    func test_memoryGraphRetriever_mostRecentInteraction_picksTrueMaxDate_notHighestScored() {
        let me = Person(name: "Me", isMe: true)
        let son = Person(name: "Aditya")
        let relationship = PersonRelationship(subject: son, type: .child, object: me)
        let sonNodeID = MemoryGraphBuilder.personNodeID(son)
        let olderEntryID = MemoryNodeID(rawValue: "entry:costco")
        let recentEntryID = MemoryNodeID(rawValue: "entry:dinner")
        let graph = MemoryGraph(
            builtAt: .now,
            nodes: [
                MemoryNode(id: sonNodeID, kind: .person, title: "Aditya"),
                MemoryNode(
                    id: olderEntryID, kind: .entry, title: "Apple Watch shopping",
                    summary: "Shopped for an Apple Watch with Aditya at Costco.",
                    date: Date(timeIntervalSince1970: 1_752_800_000),   // July 18
                    properties: ["domain": "family", "entryKind": "dailyLog"]
                ),
                MemoryNode(
                    id: recentEntryID, kind: .entry, title: "Dinner at home",
                    summary: "Had dinner together with Aditya at home.",
                    date: Date(timeIntervalSince1970: 1_753_150_000),   // July 22
                    properties: ["domain": "family", "entryKind": "dailyLog"]
                )
            ],
            edges: [
                MemoryEdge(from: sonNodeID, to: olderEntryID, kind: .mentions, label: "mentioned"),
                MemoryEdge(from: sonNodeID, to: recentEntryID, kind: .mentions, label: "mentioned")
            ],
            sourceFingerprint: "test"
        )

        let result = MemoryGraphRetriever.retrieve(
            query: "When did I last meet Aditya?",
            graph: graph, people: [me, son], relationships: [relationship], limit: 8
        )

        XCTAssertEqual(result.mostRecentInteraction?.node.id, recentEntryID,
            "Must pick the true most-recent linked entry (July 22), not whichever one the relevance score ranked higher")

        let packed = MemoryGraphContextPacker.pack(result)
        XCTAssertTrue(packed.contains("MOST RECENT WITH Aditya"))
        XCTAssertTrue(packed.contains("Dinner at home"))
    }

    @MainActor
    func test_memoryGraphRetriever_mostRecentInteraction_usesPastEntriesAndEventsOnly() {
        let me = Person(name: "Me", isMe: true)
        let friend = Person(name: "David")
        let relationship = PersonRelationship(subject: friend, type: .friend, object: me)
        let friendNodeID = MemoryGraphBuilder.personNodeID(friend)
        let pastEntryID = MemoryNodeID(rawValue: "entry:coffee")
        let futureEventID = MemoryNodeID(rawValue: "event:dinner")
        let reminderID = MemoryNodeID(rawValue: "reminder:ask")
        let conflictID = MemoryNodeID(rawValue: "conflict:old")
        let now = Date(timeIntervalSince1970: 1_753_200_000)
        let graph = MemoryGraph(
            builtAt: now,
            nodes: [
                MemoryNode(id: friendNodeID, kind: .person, title: "David"),
                MemoryNode(
                    id: pastEntryID, kind: .entry, title: "Coffee with David",
                    summary: "Met David for coffee.",
                    date: now.addingTimeInterval(-2 * 86_400)
                ),
                MemoryNode(
                    id: futureEventID, kind: .event, title: "Dinner with David",
                    summary: "Upcoming dinner reservation.",
                    date: now.addingTimeInterval(3 * 86_400)
                ),
                MemoryNode(
                    id: reminderID, kind: .reminder, title: "Ask David about school",
                    date: now.addingTimeInterval(-1 * 86_400),
                    properties: ["isDone": "false"]
                ),
                MemoryNode(
                    id: conflictID, kind: .conflict, title: "Disagreement with David",
                    date: now.addingTimeInterval(-12 * 60 * 60)
                )
            ],
            edges: [
                MemoryEdge(from: friendNodeID, to: pastEntryID, kind: .hasEntry, label: "daily log"),
                MemoryEdge(from: friendNodeID, to: futureEventID, kind: .hasEvent, label: "event"),
                MemoryEdge(from: friendNodeID, to: reminderID, kind: .hasReminder, label: "reminder"),
                MemoryEdge(from: friendNodeID, to: conflictID, kind: .hasConflict, label: "conflict")
            ],
            sourceFingerprint: "test"
        )

        let result = MemoryGraphRetriever.retrieve(
            query: "When did I last meet David?",
            graph: graph, people: [me, friend], relationships: [relationship],
            now: now, limit: 8
        )

        XCTAssertEqual(result.mostRecentInteraction?.node.id, pastEntryID,
            "Last-meet retrieval must prefer the last past interaction, not a future event, reminder, or conflict")
    }

    func test_memoryGraphRetriever_mostRecentInteraction_nilWhenIntentNotFlagged() {
        let me = Person(name: "Me", isMe: true)
        let son = Person(name: "Aditya")
        let relationship = PersonRelationship(subject: son, type: .child, object: me)
        let sonNodeID = MemoryGraphBuilder.personNodeID(son)
        let entryID = MemoryNodeID(rawValue: "entry:dinner")
        let graph = MemoryGraph(
            builtAt: .now,
            nodes: [
                MemoryNode(id: sonNodeID, kind: .person, title: "Aditya"),
                MemoryNode(id: entryID, kind: .entry, title: "Dinner at home", date: .now)
            ],
            edges: [MemoryEdge(from: sonNodeID, to: entryID, kind: .mentions, label: "mentioned")],
            sourceFingerprint: "test"
        )

        let result = MemoryGraphRetriever.retrieve(
            query: "Who is Aditya?",   // no "last time" phrasing
            graph: graph, people: [me, son], relationships: [relationship], limit: 8
        )

        XCTAssertNil(result.mostRecentInteraction)
    }

    /// Regression: "what are priorities when MEETING Akhil" pulled in an
    /// unrelated event (the user's own wisdom tooth extraction, no person
    /// associated at all) as evidence about Akhil — because the word "meeting"
    /// sets wantsEvents, and matchesStructuredIntent boosted EVERY event node
    /// in the whole graph, not just ones actually connected to Akhil. Verify an
    /// unconnected event doesn't outrank/appear alongside evidence genuinely
    /// linked to the mentioned person once a person is named.
    @MainActor
    func test_memoryGraphRetriever_structuredIntentBoost_scopedToMentionedPerson() {
        let me = Person(name: "Me", isMe: true)
        let son = Person(name: "Akhil")
        let relationship = PersonRelationship(subject: son, type: .child, object: me)
        let sonNodeID = MemoryGraphBuilder.personNodeID(son)
        let linkedEventID = MemoryNodeID(rawValue: "event:birthday")
        let unlinkedEventID = MemoryNodeID(rawValue: "event:wisdom-tooth")
        let graph = MemoryGraph(
            builtAt: .now,
            nodes: [
                MemoryNode(id: sonNodeID, kind: .person, title: "Akhil"),
                MemoryNode(
                    id: linkedEventID, kind: .event, title: "Akhil's birthday",
                    date: Date(timeIntervalSince1970: 1_754_100_000),
                    properties: ["domain": "other"]
                ),
                MemoryNode(
                    id: unlinkedEventID, kind: .event, title: "Wisdom tooth extraction",
                    date: Date(timeIntervalSince1970: 1_753_800_000),
                    properties: ["domain": "other"]
                )
            ],
            edges: [
                MemoryEdge(from: sonNodeID, to: linkedEventID, kind: .hasEvent, label: "")
                // No edge at all between Akhil and the wisdom tooth extraction.
            ],
            sourceFingerprint: "test"
        )

        let result = MemoryGraphRetriever.retrieve(
            query: "What are priorities when meeting Akhil?",
            graph: graph, people: [me, son], relationships: [relationship], limit: 8
        )

        XCTAssertTrue(result.evidenceNodes.contains { $0.id == linkedEventID },
            "Akhil's actual birthday event must still appear as evidence")
        XCTAssertFalse(result.evidenceNodes.contains { $0.id == unlinkedEventID },
            "An event with no connection to Akhil must not appear as evidence just because the question said \"meeting\"")
    }

    @MainActor
    func test_memoryGraphRetriever_expandsResolvedPersonToRelevantEvidence() {
        let me = Person(name: "Me", isMe: true)
        let spouse = Person(name: "Lilly")
        let relationship = PersonRelationship(subject: spouse, type: .spouse, object: me)
        let spouseNodeID = MemoryGraphBuilder.personNodeID(spouse)
        let entryNodeID = MemoryNodeID(rawValue: "entry:family-dinner")
        let graph = MemoryGraph(
            builtAt: .now,
            nodes: [
                MemoryNode(id: spouseNodeID, kind: .person, title: "Lilly"),
                MemoryNode(
                    id: entryNodeID,
                    kind: .entry,
                    title: "Dinner plan",
                    summary: "Remember to ask Lilly about the school form.",
                    date: .now,
                    properties: ["domain": "family", "entryKind": "dailyLog"]
                )
            ],
            edges: [
                MemoryEdge(from: spouseNodeID, to: entryNodeID, kind: .mentions, label: "mentioned")
            ],
            sourceFingerprint: "test"
        )

        let result = MemoryGraphRetriever.retrieve(
            query: "What should I ask my wife?",
            graph: graph,
            people: [me, spouse],
            relationships: [relationship],
            limit: 8
        )

        XCTAssertTrue(result.seedNodes.contains { $0.id == spouseNodeID })
        XCTAssertTrue(result.evidenceNodes.contains { $0.id == entryNodeID })
        XCTAssertTrue(result.edges.contains { $0.from == spouseNodeID && $0.to == entryNodeID })
    }

    func test_memoryGraphContextPacker_andAdvisorContext_includeGraphEvidence() {
        let entryNode = MemoryNode(
            id: MemoryNodeID(rawValue: "entry:test"),
            kind: .entry,
            title: "School form",
            summary: "Ask Lilly whether the form was submitted.",
            date: Date(timeIntervalSince1970: 1_000_000),
            properties: ["domain": "family", "entryKind": "dailyLog"]
        )
        let result = MemoryGraphRetrievalResult(
            intent: .empty(query: "What should I ask Lilly?"),
            seedNodes: [entryNode],
            expandedNodes: [entryNode],
            edges: []
        )

        let graphContext = MemoryGraphContextPacker.pack(result)
        XCTAssertTrue(graphContext.contains("School form"))
        XCTAssertTrue(graphContext.contains("dailyLog"))

        let advisorContext = AdviceService.context(
            decisions: [],
            experiences: [],
            graphContext: graphContext
        )
        XCTAssertTrue(advisorContext.contains("MEMORY GRAPH CONTEXT"))
        XCTAssertTrue(advisorContext.contains("School form"))
    }

    /// Regression: "Useful links" edge lines rendered bare internal IDs
    /// ("person:2412D008-CC51-4F2E... --relatedTo--> person:B14948F4...") with
    /// no indication of who those UUIDs actually were — opaque noise sitting
    /// right next to the correctly-named PEOPLE/Evidence blocks, discovered via
    /// the debug context viewer while investigating an inconsistent "who is
    /// Ganesh" answer. Edge lines must resolve to each node's real title.
    func test_memoryGraphContextPacker_edgeLines_resolveToTitlesNotRawIDs() {
        let meID = MemoryNodeID(rawValue: "person:me")
        let eventID = MemoryNodeID(rawValue: "event:wisdom-tooth")
        let meNode = MemoryNode(id: meID, kind: .person, title: "Ganesh Kolekar")
        let eventNode = MemoryNode(id: eventID, kind: .event, title: "Wisdom tooth extraction")
        let result = MemoryGraphRetrievalResult(
            intent: .empty(query: "Who is Ganesh?"),
            seedNodes: [meNode, eventNode],
            expandedNodes: [meNode, eventNode],
            edges: [MemoryEdge(from: meID, to: eventID, kind: .hasEvent, label: "")]
        )

        let graphContext = MemoryGraphContextPacker.pack(result)

        XCTAssertTrue(graphContext.contains("Ganesh Kolekar --hasEvent--> Wisdom tooth extraction"),
            "Edge lines must name the actual people/events, not their internal IDs")
        XCTAssertFalse(graphContext.contains("person:me"), "Must never leak a raw internal ID into the model's context")
        XCTAssertFalse(graphContext.contains("event:wisdom-tooth"), "Must never leak a raw internal ID into the model's context")
    }

    /// Regression: .relatedTo edges are built one-for-one from PersonRelationship
    /// — the same facts PersonContextBuilder already states unambiguously in the
    /// PEOPLE block ("You are Parent of Aditya Kolekar."). Once resolved to real
    /// names, "Akhil Kolekar --relatedTo--> Ganesh Kolekar (Child)" is genuinely
    /// ambiguous about which side is the child, and produced exactly this kind
    /// of misread ("Ganesh Kolekar is your parent") on-device. Verify these
    /// edges never appear in "Useful links" at all.
    func test_memoryGraphContextPacker_relatedToEdges_excludedFromUsefulLinks() {
        let meID = MemoryNodeID(rawValue: "person:me")
        let childID = MemoryNodeID(rawValue: "person:child")
        let meNode = MemoryNode(id: meID, kind: .person, title: "Ganesh Kolekar")
        let childNode = MemoryNode(id: childID, kind: .person, title: "Akhil Kolekar")
        let result = MemoryGraphRetrievalResult(
            intent: .empty(query: "Who is Ganesh?"),
            seedNodes: [meNode, childNode],
            expandedNodes: [meNode, childNode],
            edges: [MemoryEdge(from: childID, to: meID, kind: .relatedTo, label: "Child")]
        )

        let graphContext = MemoryGraphContextPacker.pack(result)

        XCTAssertFalse(graphContext.contains("relatedTo"),
            "relatedTo edges duplicate the PEOPLE block and are ambiguous once resolved to names — must never appear in Useful links")
    }

    /// Regression: "who is X and when did I last meet them" answers only had
    /// month-level dates ("July 2026") available in two independent ways —
    /// ExperienceSummary/DecisionSummary took the record's raw `createdAt`
    /// (when it was typed into the app) instead of `timelineDate` (occurredAt,
    /// the actual event date — wrong whenever an entry is backfilled or logged
    /// a day late), and the advisor context formatted whatever date it did get
    /// as "yyyy-MM", discarding the day entirely regardless. Both made a
    /// precise "when" answer physically impossible even when the model
    /// reasoned correctly. Verify a backfilled entry (occurredAt distinct from
    /// createdAt) surfaces its real event date, at day precision, in context.
    @MainActor
    func test_advisorContext_usesEventDateNotRecordCreationDate_atDayPrecision() {
        let loggedLate = Date(timeIntervalSince1970: 1_785_000_000)   // when it was typed in
        let actualEvent = Date(timeIntervalSince1970: 1_752_000_000)  // the real, earlier event date
        let experience = Experience(
            createdAt: loggedLate, title: "Coffee with David", summary: "Caught up after a long time.",
            occurredAt: actualEvent
        )
        let decision = Decision(
            createdAt: loggedLate, title: "Switched banks", statement: "Moved to a new bank.",
            occurredAt: actualEvent
        )

        let experienceSummary = ExperienceSummary(experience)
        let decisionSummary = DecisionSummary(decision)
        XCTAssertEqual(experienceSummary.createdAt, actualEvent,
            "Advisor context must use the experience's actual event date, not when it was logged")
        XCTAssertEqual(decisionSummary.createdAt, actualEvent,
            "Advisor context must use the decision's actual event date, not when it was logged")

        let context = AdviceService.context(decisions: [decisionSummary], experiences: [experienceSummary])
        let expectedDayString: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: actualEvent)
        }()
        XCTAssertTrue(context.contains(expectedDayString),
            "Context must render the full event date (day precision), not just year-month")
    }

    /// Regression: 18 decisions + 32 experiences (an ordinary amount of history
    /// for an active user, each capped to 12 but with every field populated) plus
    /// a People profile and graph context measured at 4094 tokens on-device — over
    /// the FoundationModels session's 4096-token window, with the request failing
    /// outright (GenerationError.exceededContextWindowSize) since that left no
    /// room to generate a response. The People/graph blocks are ground truth and
    /// usually small; Decisions/Experiences are the bulky, lower-precision
    /// fallback — verify a heavy journal keeps the small, high-priority blocks
    /// and drops enough of the bulky ones to stay within a safe character budget,
    /// rather than assembling an unbounded string.
    func test_advisorContext_withHeavyHistory_staysWithinCharacterBudget() {
        let longText = String(repeating: "Detailed context about what happened and why it mattered. ", count: 6)
        let decisions = (0..<18).map { i in
            DecisionSummary(
                id: UUID(), createdAt: Date(timeIntervalSince1970: TimeInterval(i) * 86_400),
                title: "Decision \(i)", statement: longText, rationale: longText,
                domain: "family", stakes: "medium", outcome: longText
            )
        }
        let experiences = (0..<32).map { i in
            ExperienceSummary(
                id: UUID(), createdAt: Date(timeIntervalSince1970: TimeInterval(i) * 86_400),
                title: "Experience \(i)", summary: longText, feelings: longText,
                tone: "pleasant", factors: longText, learning: longText,
                domain: "family", tags: [], outcomes: [longText]
            )
        }
        let people = [PersonProfileSummary(id: UUID(), text: "Akhil: no recorded relationship to anyone else in People.")]

        let context = AdviceService.context(
            decisions: decisions, experiences: experiences, people: people
        )

        XCTAssertLessThanOrEqual(context.count, 1_300,
            "Assembled context must stay within the safe on-device character budget regardless of journal size")
        XCTAssertTrue(context.contains("Akhil"),
            "The small, high-priority People block must survive even when the bulky Decisions/Experiences blocks are trimmed")
    }

    /// Regression: the character budget itself was recalibrated after a real
    /// on-device failure — a 6,000-char budget still measured 4,091 tokens
    /// (dense structured content tokenizes far less efficiently than the
    /// ~4-chars/token assumption it was based on). This guards the actual
    /// invariant that matters regardless of any future recalibration: a single
    /// oversized block (in practice, MEMORY GRAPH CONTEXT with a lot of graph
    /// data) must be TRUNCATED to fit, never skipped whole while leaving room
    /// unused, and the total must never exceed the budget no matter how large
    /// any one block is.
    func test_advisorContext_oversizedSingleBlock_isTruncatedNotSkipped_andNeverExceedsBudget() {
        let hugeGraphContext = String(repeating: "1. [entry, 2026-07-15] Something happened. ", count: 500)
        let context = AdviceService.context(
            decisions: [], experiences: [], graphContext: hugeGraphContext
        )

        XCTAssertLessThanOrEqual(context.count, 1_300,
            "A single oversized block must never be allowed to blow past the budget")
        XCTAssertTrue(context.contains("MEMORY GRAPH CONTEXT"),
            "The oversized block should be truncated into the budget, not dropped entirely")
    }

    /// Regression: a real oversized MEMORY GRAPH CONTEXT block was cut off
    /// mid-word inside a real evidence line ("...Argument with Alex ab…"),
    /// handing the model a dangling, unfinished sentence as part of its own
    /// input. Truncation must snap to the last complete line instead of an
    /// arbitrary character position, even though that means using a little
    /// less than the full budget.
    func test_advisorContext_oversizedBlock_truncatesAtLineBoundary_notMidWord() {
        let line = "1. [entry, 2026-07-01] A complete evidence line of fixed length here.\n"
        let graphContext = "Evidence:\n" + String(repeating: line, count: 40)   // well over budget

        let context = AdviceService.context(decisions: [], experiences: [], graphContext: graphContext)

        XCTAssertLessThanOrEqual(context.count, 1_300)
        guard let ellipsisRange = context.range(of: "…") else {
            XCTFail("This oversized block should have required truncation")
            return
        }
        let charBeforeEllipsis = context.index(before: ellipsisRange.lowerBound)
        XCTAssertEqual(context[charBeforeEllipsis], "\n",
            "Truncation must land right after a complete line, never mid-word")
    }

    /// Regression: "priorities to celebrate Akhil's birthday" produced a
    /// response that repeated the exact same four-sentence PEOPLE-derived
    /// block roughly ten times in a row until it hit maximumResponseTokens —
    /// a self-copy loop, not a wrong fact. Once a sentence repeats one
    /// already seen, keep only what came before the first repeat.
    func test_stripRepetition_truncatesAtFirstRepeatedSentence() {
        let looping = "Akhil is your child. Akhil is Sibling of Aditya Kolekar. "
            + "Akhil is your child. Akhil is Sibling of Aditya Kolekar. "
            + "Akhil is your child. Akhil is Sibling of Aditya Kolekar."

        let result = AdviceService.stripRepetition(looping)

        XCTAssertEqual(result, "Akhil is your child. Akhil is Sibling of Aditya Kolekar.",
            "Must stop at the first sentence that repeats one already seen in this response")
    }

    func test_stripRepetition_leavesNonRepeatingAnswerUnchanged() {
        let answer = "Plan a small gathering with Akhil's favorite chocolate ice cream cake. "
            + "Invite Aditya since they're siblings. Keep it low-key on a weeknight."

        XCTAssertEqual(AdviceService.stripRepetition(answer), answer)
    }

    func test_stripRepetition_doesNotFlagShortRepeatedFragments() {
        // Short fragments ("Yes", a lone clause) recur naturally in normal
        // prose and shouldn't be mistaken for a degenerate loop.
        let answer = "Yes. Bring a cake. Yes, that should be enough for the party."
        XCTAssertEqual(AdviceService.stripRepetition(answer), answer)
    }

    @MainActor
    func test_adviceViewModel_ignoresStaleRequestCompletions() async {
        let service = SequencedAdviceService()
        let viewModel = AdviceViewModel(advisor: service, speech: MockSpeechService())

        viewModel.question = "old question"
        let old = viewModel.beginAsk()!
        viewModel.question = "new question"
        let new = viewModel.beginAsk()!

        await viewModel.ask(
            requestID: new.id,
            question: new.question,
            decisions: [],
            experiences: []
        )
        await viewModel.ask(
            requestID: old.id,
            question: old.question,
            decisions: [],
            experiences: []
        )

        XCTAssertEqual(viewModel.phase, .answer("answer for new question"))
    }

    /// The dedicated "who is X" path (routed to from AdviceView when
    /// QueryIntentDraft.questionType == "who_is" AND a person was actually
    /// resolved) must reach AdvisingServicing.answerWhoIs, not the generic
    /// advise() path — otherwise the whole point of skipping decisions/
    /// experiences/graph-context assembly for a pure identity question is lost.
    @MainActor
    func test_adviceViewModel_askWhoIs_answersFromDedicatedPath() async {
        let service = SequencedAdviceService()
        let viewModel = AdviceViewModel(advisor: service, speech: MockSpeechService())

        viewModel.question = "who is Akhil"
        let request = viewModel.beginAsk()!

        await viewModel.askWhoIs(
            requestID: request.id,
            question: request.question,
            people: [PersonProfileSummary(id: UUID(), text: "Akhil: no recorded relationship to anyone else in People.")]
        )

        XCTAssertEqual(viewModel.phase, .answer("who-is answer for who is Akhil"))
    }

    /// Regression: "who is Connor" (a name never saved as a Person) fell
    /// through to the generic advise() pipeline, which had no evidence
    /// mentioning "Connor" at all — the model still answered, fabricating
    /// "Connor is Akhil's friend" and citing an entry that never named him.
    /// The real (non-mock) AdviceService must short-circuit to a deterministic
    /// non-answer for an unresolved name, with no model call, so there's no
    /// text generation step left that could invent a relationship.
    func test_adviceService_answerWhoIs_unresolvedName_answersDeterministically_noModelCall() async throws {
        let service = AdviceService()
        let answer = try await service.answerWhoIs(question: "who is Connor", people: [])
        XCTAssertEqual(answer, "I don't have anyone by that name in your People list.")
    }

    @MainActor
    func test_adviceViewModel_askWhoIs_ignoresStaleRequestCompletions() async {
        let service = SequencedAdviceService()
        let viewModel = AdviceViewModel(advisor: service, speech: MockSpeechService())

        viewModel.question = "who is old"
        let old = viewModel.beginAsk()!
        viewModel.question = "who is new"
        let new = viewModel.beginAsk()!

        await viewModel.askWhoIs(requestID: new.id, question: new.question, people: [])
        await viewModel.askWhoIs(requestID: old.id, question: old.question, people: [])

        XCTAssertEqual(viewModel.phase, .answer("who-is answer for who is new"))
    }

    // MARK: - Forward-looking time intent

    /// resolveTimeRange only understood backward-looking phrases (today,
    /// yesterday, this week, recently), so "tonight" / "next week" resolved to
    /// no range at all and a question about an upcoming interaction fell back
    /// to undated relevance.
    @MainActor
    func test_memoryQueryResolver_resolvesForwardLookingTimePhrases() {
        func range(_ query: String) -> DateInterval? {
            MemoryQueryResolver.resolve(query: query, people: [], relationships: []).timeRange
        }

        XCTAssertNotNil(range("what should I ask Lilly before dinner tonight?"),
            "'tonight' must resolve to a time range")
        XCTAssertNotNil(range("what are the priorities meeting Lilly next week?"),
            "'next week' must resolve to a time range")
        XCTAssertNotNil(range("anything I should prepare tomorrow?"),
            "'tomorrow' must resolve to a time range")
        XCTAssertNotNil(range("what is upcoming with Lilly?"),
            "'upcoming' must resolve to a time range")
    }

    /// "next week" must land in the future, not be silently read as the past —
    /// the previous ranges all ended at `now`.
    @MainActor
    func test_memoryQueryResolver_nextWeekRangeIsInTheFuture() {
        let now = Date()
        let intent = MemoryQueryResolver.resolve(
            query: "what are the priorities meeting Lilly next week?",
            people: [], relationships: [], now: now
        )
        let range = try? XCTUnwrap(intent.timeRange)
        XCTAssertNotNil(range)
        if let range { XCTAssertGreaterThan(range.end, now, "'next week' must extend past now") }
    }

    /// With a resolved window, evidence inside it must outrank evidence far
    /// outside it. Before timeProximityBoost both scored identically and only
    /// separated on the UUID-string tie-break in the ranking sort.
    @MainActor
    func test_memoryGraphRetriever_tonightQuestion_ranksTonightAboveNextWeek() {
        let now = Date()
        let me = Person(name: "Ganesh", isMe: true)
        let lilly = Person(name: "Lilly")
        let spouse = PersonRelationship(subject: lilly, type: .spouse, object: me)

        let tonight = Event(title: "Dinner with Lilly", date: now.addingTimeInterval(3 * 3_600), person: lilly)
        let nextWeek = Event(title: "Travel plan review with Lilly", date: now.addingTimeInterval(8 * 86_400), person: lilly)

        let graph = MemoryGraphBuilder.build(
            experiences: [], events: [tonight, nextWeek], decisions: [],
            people: [me, lilly], relationships: [spouse],
            conflicts: [], reminders: []
        )

        let result = MemoryGraphRetriever.retrieve(
            query: "what should I ask Lilly before dinner tonight?",
            graph: graph, people: [me, lilly], relationships: [spouse], now: now, limit: 24
        )

        let titles: [String] = result.evidenceNodes.map { $0.title }
        guard let tonightIndex = titles.firstIndex(of: "Dinner with Lilly") else {
            return XCTFail("Tonight's event must reach evidence; got \(titles)")
        }
        if let nextWeekIndex = titles.firstIndex(of: "Travel plan review with Lilly") {
            XCTAssertLessThan(tonightIndex, nextWeekIndex,
                "Evidence inside the asked-about window must outrank evidence a week outside it")
        }
    }

    // MARK: - Grounding validation

    private func packedContext(evidence: [String] = ["Coffee with Bradley", "Recruiter call"],
                               people: Set<String> = ["Bradley", "Lilly Kolekar"],
                               dates: Set<String> = ["2026-08-13"]) -> MemoryGraphContextPacker.PackedContext {
        MemoryGraphContextPacker.PackedContext(
            text: "Evidence:\n1. Coffee with Bradley\n2. Recruiter call",
            evidenceTitles: evidence, knownPeople: people, knownDates: dates
        )
    }

    @MainActor
    func test_groundingValidator_answerCitingSuppliedEvidence_isGrounded() {
        let answer = GroundedAnswer(
            answer: "You met Bradley about the platform architect role.",
            citedEvidence: [1, 2], citedPeople: ["Bradley"],
            citedDates: ["2026-08-13"], usedGeneralKnowledge: false
        )
        let report = GroundingValidator.validate(answer, against: packedContext())
        XCTAssertTrue(report.isGrounded)
        XCTAssertFalse(report.hasFindings)
    }

    /// The core case: an Evidence number the model was never shown.
    @MainActor
    func test_groundingValidator_flagsEvidenceNumberNotInContext() {
        let answer = GroundedAnswer(
            answer: "Per entry 7 you decided to leave.", citedEvidence: [1, 7],
            citedPeople: [], citedDates: [], usedGeneralKnowledge: false
        )
        let report = GroundingValidator.validate(answer, against: packedContext())
        XCTAssertEqual(report.unknownEvidence, [7])
        XCTAssertFalse(report.isGrounded)
    }

    /// The failure already seen in this app: a person named who appears nowhere
    /// in the context.
    @MainActor
    func test_groundingValidator_flagsPersonNotInContext() {
        let answer = GroundedAnswer(
            answer: "Connor mentioned the referral.", citedEvidence: [1],
            citedPeople: ["Connor"], citedDates: [], usedGeneralKnowledge: false
        )
        let report = GroundingValidator.validate(answer, against: packedContext())
        XCTAssertEqual(report.unknownPeople, ["Connor"])
        XCTAssertFalse(report.isGrounded)
    }

    /// A first name must match a fuller name in the context — the answer may
    /// reasonably say "Lilly" where the context says "Lilly Kolekar".
    @MainActor
    func test_groundingValidator_acceptsFirstNameOfAFullerContextName() {
        let answer = GroundedAnswer(
            answer: "Lilly is your spouse.", citedEvidence: [1],
            citedPeople: ["lilly"], citedDates: [], usedGeneralKnowledge: false
        )
        XCTAssertTrue(GroundingValidator.validate(answer, against: packedContext()).isGrounded)
    }

    @MainActor
    func test_groundingValidator_flagsDateNotInContext() {
        let answer = GroundedAnswer(
            answer: "That was on 2020-01-01.", citedEvidence: [1],
            citedPeople: [], citedDates: ["2020-01-01"], usedGeneralKnowledge: false
        )
        let report = GroundingValidator.validate(answer, against: packedContext())
        XCTAssertEqual(report.unknownDates, ["2020-01-01"])
    }

    /// Specific claims with no citation are unverifiable — surfaced separately
    /// from an outright fabricated reference.
    @MainActor
    func test_groundingValidator_flagsSpecificClaimsWithNoCitation() {
        let answer = GroundedAnswer(
            answer: "Bradley called on 2026-08-13.", citedEvidence: [],
            citedPeople: ["Bradley"], citedDates: ["2026-08-13"], usedGeneralKnowledge: false
        )
        let report = GroundingValidator.validate(answer, against: packedContext())
        XCTAssertTrue(report.citesNothing)
        XCTAssertTrue(report.isGrounded, "Nothing was fabricated — it just cannot be checked")
        XCTAssertTrue(report.hasFindings)
    }

    /// General guidance that names nobody is a legitimate answer, not a finding.
    @MainActor
    func test_groundingValidator_generalGuidanceWithNoCitationIsNotFlagged() {
        let answer = GroundedAnswer(
            answer: "Your history doesn't cover this; keep notes as you go.",
            citedEvidence: [], citedPeople: [], citedDates: [], usedGeneralKnowledge: true
        )
        let report = GroundingValidator.validate(answer, against: packedContext())
        XCTAssertFalse(report.hasFindings)
    }

    /// The manifest must describe what was actually packed, or validation is
    /// checking against the wrong thing.
    @MainActor
    func test_packWithManifest_manifestMatchesWhatWasPacked() {
        let now = Date()
        let me = Person(name: "Ganesh", isMe: true)
        let lilly = Person(name: "Lilly")
        let spouse = PersonRelationship(subject: lilly, type: .spouse, object: me)
        let dinner = Event(title: "Dinner with Lilly", date: now, person: lilly)

        let graph = MemoryGraphBuilder.build(
            experiences: [], events: [dinner], decisions: [],
            people: [me, lilly], relationships: [spouse], conflicts: [], reminders: []
        )
        let result = MemoryGraphRetriever.retrieve(
            query: "what should I ask Lilly tonight?",
            graph: graph, people: [me, lilly], relationships: [spouse], now: now, limit: 24
        )
        let packed = MemoryGraphContextPacker.packWithManifest(result)

        XCTAssertEqual(packed.text, MemoryGraphContextPacker.pack(result),
            "The String wrapper must return exactly the manifest's text")
        for title in packed.evidenceTitles {
            XCTAssertTrue(packed.text.contains(title),
                "Manifest lists '\(title)' but the packed context never mentions it")
        }
        XCTAssertTrue(packed.knownPeople.contains("Lilly"),
            "A resolved person must be citable; got \(packed.knownPeople)")
    }

    // MARK: - Unknown-identity backstop

    /// The reported failure: "who is Tommy?" for a name never saved reached the
    /// generic pipeline (its classifier said "generic", the fallback default)
    /// and came back "Tommy is your brother."
    @MainActor
    func test_whoIsDetector_catchesBareUnknownName() {
        XCTAssertEqual(WhoIsQuestionDetector.candidateName(in: "who is Tommy?"), "tommy")
        XCTAssertEqual(WhoIsQuestionDetector.candidateName(in: "Who's Bradley"), "bradley")
        XCTAssertEqual(WhoIsQuestionDetector.candidateName(in: "who is Anne-Marie?"), "anne-marie")
        XCTAssertEqual(WhoIsQuestionDetector.candidateName(in: "how am I related to Priya?"), "priya")
    }

    /// Must not fire on questions that merely start "who is" — those have real
    /// answers and would be wrongly refused with "I don't have anyone by that name".
    @MainActor
    func test_whoIsDetector_ignoresNonIdentityQuestions() {
        for query in ["who is coming to dinner tomorrow?",
                      "who is my manager?",
                      "who is responsible for the deadline slip?",
                      "who is going to the party with Alex?",
                      "what should I ask Lilly tonight?",
                      "who is the person that helped me with the dashboard work last week?"] {
            XCTAssertFalse(WhoIsQuestionDetector.looksLikeIdentityQuestion(query),
                "Should not short-circuit: \(query)")
        }
    }

    /// Smart quotes come from iOS keyboards; the straight and curly forms must
    /// behave identically.
    @MainActor
    func test_whoIsDetector_handlesTypographicApostrophe() {
        XCTAssertEqual(WhoIsQuestionDetector.candidateName(in: "Who\u{2019}s Tommy?"), "tommy")
    }

    /// The safe answer itself — no model call, so nothing can be fabricated.
    @MainActor
    func test_answerWhoIs_withNoResolvedPeople_refusesDeterministically() async throws {
        let answer = try await AdviceService().answerWhoIs(question: "who is Tommy?", people: [])
        XCTAssertTrue(answer.contains("don't have anyone by that name"),
            "An unresolved name must get the deterministic refusal; got: \(answer)")
    }

    // MARK: - Unresolved-but-mentioned people

    /// Builds a graph where "Tommy" is named in entries but was never added as
    /// a Person — the state MemoryGraphBuilder records as a
    /// `person-unresolved:` node.
    @MainActor
    private func graphMentioningTommy(entryCount: Int, now: Date) -> MemoryGraph {
        let me = Person(name: "Ganesh", isMe: true)
        let experiences = (0..<entryCount).map { i in
            Experience(
                id: UUID(), createdAt: now.addingTimeInterval(-Double(i + 1) * 86_400),
                title: "Day \(i) with Tommy",
                summary: "Spent time with Tommy.",
                tone: .pleasant, domain: .family, people: ["Tommy"]
            )
        }
        return MemoryGraphBuilder.build(
            experiences: experiences, events: [], decisions: [],
            people: [me], relationships: [], conflicts: [], reminders: []
        )
    }

    @MainActor
    func test_unresolvedPersonFinder_findsNameMentionedButNotInPeople() {
        let now = Date()
        let found = UnresolvedPersonFinder.find(
            name: "tommy", in: graphMentioningTommy(entryCount: 2, now: now), now: now
        )
        let mention = try? XCTUnwrap(found)
        XCTAssertNotNil(mention)
        XCTAssertEqual(found?.totalCount, 2)
        XCTAssertEqual(found?.name, "Tommy", "Should use the journal's own spelling")
        XCTAssertTrue(found?.answerText.contains("isn't in your People list") ?? false)
        XCTAssertTrue(found?.answerText.contains("add Tommy to your People list") ?? false)
    }

    /// Caps cited mentions at 3 while still reporting the true total.
    @MainActor
    func test_unresolvedPersonFinder_capsCitationsAtThree() {
        let now = Date()
        let found = UnresolvedPersonFinder.find(
            name: "tommy", in: graphMentioningTommy(entryCount: 7, now: now), now: now
        )
        XCTAssertEqual(found?.mentions.count, 3)
        XCTAssertEqual(found?.totalCount, 7)
        XCTAssertTrue(found?.answerText.contains("and 4 more") ?? false,
            "Got: \(found?.answerText ?? "nil")")
    }

    /// Most recent first, so the three shown are the three that matter.
    @MainActor
    func test_unresolvedPersonFinder_citesMostRecentFirst() {
        let now = Date()
        let found = UnresolvedPersonFinder.find(
            name: "tommy", in: graphMentioningTommy(entryCount: 5, now: now), now: now
        )
        let dates = found?.mentions.compactMap(\.date) ?? []
        XCTAssertEqual(dates, dates.sorted(by: >), "Mentions must be newest first")
    }

    /// The window is applied explicitly — the graph itself has no date bound.
    @MainActor
    func test_unresolvedPersonFinder_ignoresMentionsOlderThanAYear() {
        let now = Date()
        let me = Person(name: "Ganesh", isMe: true)
        let old = Experience(
            id: UUID(), createdAt: now.addingTimeInterval(-400 * 86_400),
            title: "Ancient day with Tommy", summary: "Long ago.",
            tone: .pleasant, domain: .family, people: ["Tommy"]
        )
        let graph = MemoryGraphBuilder.build(
            experiences: [old], events: [], decisions: [],
            people: [me], relationships: [], conflicts: [], reminders: []
        )
        XCTAssertNil(UnresolvedPersonFinder.find(name: "tommy", in: graph, now: now),
            "A mention older than the lookback window must not be cited")
    }

    /// A name nobody has ever written must stay unknown — that is the case the
    /// deterministic refusal exists for.
    @MainActor
    func test_unresolvedPersonFinder_returnsNilForNameNeverMentioned() {
        let now = Date()
        XCTAssertNil(UnresolvedPersonFinder.find(
            name: "connor", in: graphMentioningTommy(entryCount: 3, now: now), now: now
        ))
    }

    /// A real Person must never be reported as unresolved, or adding someone
    /// would not stop the prompt.
    @MainActor
    func test_unresolvedPersonFinder_ignoresPeopleWhoAreInTheList() {
        let now = Date()
        let me = Person(name: "Ganesh", isMe: true)
        let tommy = Person(name: "Tommy")
        let entry = Experience(
            id: UUID(), createdAt: now.addingTimeInterval(-86_400),
            title: "Day with Tommy", summary: "Spent time with Tommy.",
            tone: .pleasant, domain: .family, people: ["Tommy"]
        )
        entry.linkedPeople = [tommy]
        let graph = MemoryGraphBuilder.build(
            experiences: [entry], events: [], decisions: [],
            people: [me, tommy], relationships: [], conflicts: [], reminders: []
        )
        XCTAssertNil(UnresolvedPersonFinder.find(name: "tommy", in: graph, now: now),
            "Tommy is in People — this path must not fire")
    }
}

private final class SequencedAdviceService: AdvisingServicing {
    func advise(
        question: String,
        decisions: [DecisionSummary],
        experiences: [ExperienceSummary],
        reminders: [ReminderSummary],
        events: [EventSummary],
        people: [PersonProfileSummary],
        graphContext: String
    ) async throws -> String {
        "answer for \(question)"
    }

    func eventAdvice(
        event: String,
        when: Date,
        weather: String?,
        decisions: [DecisionSummary],
        experiences: [ExperienceSummary]
    ) async throws -> String {
        ""
    }

    func extractIntent(from question: String) async throws -> QueryIntentDraft {
        QueryIntentDraft(tone: "", domain: "", topicKeywords: [], sortOrder: "recent", limit: 0, questionType: "generic")
    }

    func answerWhoIs(question: String, people: [PersonProfileSummary]) async throws -> String {
        "who-is answer for \(question)"
    }
}

private final class MockSpeechService: SpeechServicing {
    var transcript: String = ""
    var isRecording: Bool = false

    func requestAuthorization() async -> Bool { true }
    func startRecording() async throws { isRecording = true }
    func stopRecording() { isRecording = false }

}
