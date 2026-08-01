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

        XCTAssertLessThanOrEqual(context.count, 3_100,
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

        XCTAssertLessThanOrEqual(context.count, 3_100,
            "A single oversized block must never be allowed to blow past the budget")
        XCTAssertTrue(context.contains("MEMORY GRAPH CONTEXT"),
            "The oversized block should be truncated into the budget, not dropped entirely")
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
        QueryIntentDraft(tone: "", domain: "", topicKeywords: [], sortOrder: "recent", limit: 0)
    }
}

private final class MockSpeechService: SpeechServicing {
    var transcript: String = ""
    var isRecording: Bool = false

    func requestAuthorization() async -> Bool { true }
    func startRecording() async throws { isRecording = true }
    func stopRecording() { isRecording = false }
}
