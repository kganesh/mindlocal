import SwiftUI
import SwiftData

/// Ask-AI tab: answers questions grounded in the user's saved decisions (spec §9).
struct AdviceView: View {
    @Query(sort: \Decision.createdAt, order: .reverse) private var decisions: [Decision]
    @Query(sort: \Experience.createdAt, order: .reverse) private var experiences: [Experience]
    @Query(sort: \Reminder.createdAt, order: .reverse) private var reminders: [Reminder]
    @Query(sort: \Event.date, order: .reverse) private var events: [Event]
    @Query(sort: \MemoryGraphSnapshot.builtAt, order: .reverse) private var graphSnapshots: [MemoryGraphSnapshot]
    @Query private var people: [Person]
    @Query private var relationships: [PersonRelationship]
    @State private var viewModel = AdviceViewModel()
    @State private var speaker = SpeechSpeaker()
    @State private var showingHowIDecide = false
    @FocusState private var isQuestionFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AlbumHeading(title: "remember when", subtitle: "A little perspective, from your own words.")
                        .padding(.bottom, 8)
                    // The controls sit on their own row under the text rather
                    // than floating in the field's bottom-right corner. Pinning
                    // them there meant reserving a trailing column down the
                    // field's whole height, so a question wrapped at about 60%
                    // of the width even on the first line, where nothing was
                    // beside it. A row below costs one line of height and gives
                    // the text the full width back.
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Ask about your memories…", text: $viewModel.question, axis: .vertical)
                            .lineLimit(3...8)
                            .frame(minHeight: 66, alignment: .top)
                            .focused($isQuestionFocused)
                            // Declared on the field, not on an ancestor. Inside
                            // a TabView a keyboard toolbar attached further up
                            // the hierarchy silently fails to render, which is
                            // why the first attempt at this produced no Done
                            // button at all.
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button { isQuestionFocused = false } label: {
                                        Image(systemName: "checkmark")
                                            .fontWeight(.semibold)
                                    }
                                    .accessibilityLabel("Done")
                                }
                            }

                        // Clear sits at the far end, away from mic and send.
                        // It is the one destructive control here and it was a
                        // thumb's width from the one tapped most often, so
                        // reaching for the mic could empty the field instead.
                        HStack(spacing: 10) {
                            if !viewModel.question.isEmpty {
                                Button {
                                    // Clearing used to end the dictation and
                                    // leave the recording running, which is the
                                    // worst of both: the button stayed red, and
                                    // nothing said after that appeared, because
                                    // the view model had already been told to
                                    // ignore every transcript still arriving.
                                    viewModel.stopDictating()
                                    viewModel.question = ""
                                    // Keep the keyboard up: clearing is almost
                                    // always the start of retyping, not the end
                                    // of asking.
                                    isQuestionFocused = true
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .frame(width: 38, height: 38)
                                        .foregroundStyle(AlbumTheme.Field.accessory)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear question")
                                .transition(.opacity)
                            }

                            Spacer(minLength: 0)

                            // Same pair, same order, same shapes as the writing
                            // card on Today: a bare mic glyph, then a filled
                            // arrow that sends.
                            // One or the other, never both. An empty field
                            // offers the mic; once there is a question it
                            // offers the way to send it.
                            //
                            // The mic stays while recording even though text is
                            // streaming in, because it is also the stop button,
                            // and swapping it away mid-dictation would leave no
                            // way to stop.
                            if viewModel.question.isEmpty || viewModel.speech.isRecording {
                            Button {
                                toggleMic()
                            } label: {
                                Image(systemName: viewModel.speech.isRecording ? "stop.fill" : "mic")
                                    // Matched to the send arrow by eye, not by
                                    // number. Same weight, two points larger: a
                                    // mic is a tall narrow glyph with no fill
                                    // behind it, so at the arrow's exact size it
                                    // reads smaller.
                                    .font(.system(size: 19, weight: .semibold))
                                    .frame(width: 38, height: 38)
                                    .foregroundStyle(viewModel.speech.isRecording ? .red : AlbumTheme.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(viewModel.speech.isRecording ? "Stop recording" : "Ask by voice")
                            } else {
                                // Shown on "has text" rather than canAsk, which
                                // also excludes .thinking — it has to stay while
                                // an answer is coming, because that is where the
                                // spinner lives.
                                Button {
                                    submitQuestion()
                                } label: {
                                    Group {
                                        if viewModel.phase == .thinking {
                                            ProgressView().tint(AlbumTheme.onAccent)
                                        } else {
                                            Image(systemName: "arrow.up").font(.body.weight(.semibold))
                                        }
                                    }
                                    .frame(width: 54, height: 38)
                                    .foregroundStyle(viewModel.canAsk ? AlbumTheme.onAccent : AlbumTheme.Button.disabledLabel)
                                    .background(viewModel.canAsk ? AlbumTheme.accent : AlbumTheme.Button.disabledFill,
                                                in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(!viewModel.canAsk)
                                .accessibilityLabel("Ask")
                            }
                        }
                    }
                    .padding(14)
                    .background(AlbumTheme.Field.background, in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(
                                isQuestionFocused ? AlbumTheme.Field.focusedBorder : AlbumTheme.Field.border,
                                lineWidth: isQuestionFocused ? 1.5 : 1
                            )
                    }
                    // Tapping the card's own padding, not just the text, starts
                    // a question. The screen-wide tap gesture below dismisses
                    // the keyboard, so without this the quiet area inside the
                    // field does the opposite of what it looks like it does.
                    .contentShape(RoundedRectangle(cornerRadius: 18))
                    .onTapGesture { isQuestionFocused = true }
                    .animation(.snappy(duration: 0.15), value: viewModel.question.isEmpty)
                    .animation(.snappy(duration: 0.15), value: viewModel.speech.isRecording)
                    .animation(.snappy(duration: 0.15), value: isQuestionFocused)
                    // Frozen while an answer is coming. Editing the question
                    // mid-flight does not change what was asked, so the answer
                    // would arrive about text no longer on screen. The whole
                    // card goes, not just the field: starting dictation would
                    // overwrite the question, and clearing it would leave an
                    // answer with nothing above it.
                    .disabled(viewModel.phase == .thinking)
                    // Stream the spoken question into the field while recording.
                    .onChange(of: viewModel.speech.transcript) { _, newValue in
                        if viewModel.speech.isTranscribing { viewModel.applyTranscript(newValue) }
                    }
                    .onChange(of: isQuestionFocused) { _, focused in
                        // Typing ends the dictation. The mic button clears
                        // focus before it starts, so focus arriving while the
                        // mic is live means the user has tapped in to edit —
                        // and a dictation left open would replay the transcript
                        // over that edit when the entry is sent. What is on
                        // screen at the moment of tapping in is what is kept;
                        // the trailing second of audio is dropped rather than
                        // landing on top of a correction being typed.
                        if focused, viewModel.speech.isRecording {
                            viewModel.stopDictating()
                        }
                    }

                    content

                    Spacer(minLength: 0)

                    groundedFooter
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.immediately)
            // .interactively needs scrollable content to drag, and this screen
            // is mostly empty — so on Ask it often has nothing to grab. Both
            // additions below give the keyboard a way out that does not depend
            // on there being enough content to scroll.
            .contentShape(Rectangle())
            .onTapGesture {
                if isQuestionFocused { isQuestionFocused = false }
            }
            .albumScreen()
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingHowIDecide = true } label: {
                        Image(systemName: "brain.head.profile")
                    }
                    .accessibilityLabel("How I decide")
                }
            }
            .sheet(isPresented: $showingHowIDecide) { HowIDecideView() }
            .onDisappear { speaker.stop() }
        }
    }

    /// The whole retrieval-and-answer pipeline, lifted out of the button label
    /// so the button can live inside the question field.
    private func submitQuestion() {
        isQuestionFocused = false
        Task {
            // The last second of dictation arrives after the mic stops, so the
            // question is read only once the transcript is complete.
            await viewModel.speech.finishRecording()

            // Then take the transcript from the service rather than trusting
            // the field. The observer that mirrors one into the other is a view
            // update, and it can run after this point, so the field is not
            // reliably current the instant finishRecording returns.
            //
            // Through applyTranscript, so the baseline is respected: a question
            // half typed and half spoken keeps both halves. It is a no-op when
            // no dictation is outstanding, which is what stops a stale
            // transcript landing on a question that was typed.
            viewModel.applyTranscript(viewModel.speech.transcript)
            viewModel.endDictation()

            guard let request = viewModel.beginAsk() else { return }
            let query = request.question
            // What is this question asking FOR — a tone, topic,
            // count, sort? Read once, up front, so both the
            // structured and semantic passes can use it.
            let intent = await viewModel.extractIntent(for: query)

            // Anyone named in the question gets their actual
            // People-graph profile included as ground truth, not
            // just whatever text happens to rank as similar.
            // Computed up front (cheap) since it also gates the
            // "who is X" fast path below.
            let mentionedPeople = PersonContextBuilder.mentionedPeople(in: query, among: people)
            let peopleSummaries = mentionedPeople.map {
                PersonProfileSummary(
                    id: $0.id,
                    text: PersonContextBuilder.profile(for: $0, relationships: relationships)
                )
            }

            // Route every "who_is"-classified question here,
            // whether or not a known person was resolved —
            // askWhoIs/answerWhoIs handles both outcomes
            // deterministically-safely: a resolved person
            // answers from their People profile alone (no
            // decisions/experiences/graph-context noise to
            // blend in), and an unresolved name gets a plain
            // "I don't have anyone by that name" with no model
            // call at all — falling through to the generic
            // pipeline for an unresolved name was what let the
            // model fabricate a relationship for someone never
            // saved as a Person, citing an entry that never
            // mentioned them.
            // A "who_is" classification is only safe to act on
            // when the question actually names someone. The
            // classifier keys on the word "who", so "who have I
            // been spending time with lately?" comes back as
            // who_is even though it names nobody — and the
            // deterministic branch then answers "I don't have
            // anyone by that name in your People list", which is
            // a non-sequitur to a question that asked for a list.
            //
            // Requiring either a resolved person or a candidate
            // name keeps the guard doing its job (an unknown NAME
            // still never reaches the model) while letting
            // aggregate questions about people fall through to
            // the pipeline that can actually answer them.
            let namesSomeone = !peopleSummaries.isEmpty
                || WhoIsQuestionDetector.candidateName(in: query) != nil
            guard intent.questionType != "who_is" || !namesSomeone else {
                await viewModel.askWhoIs(
                    requestID: request.id, question: query,
                    people: peopleSummaries
                )
                return
            }

            // Backstop for the same hole when the classifier
            // misses it. questionType comes from a model call
            // whose failure fallback is "generic" — the unsafe
            // path — so a failed or wrong classification sent
            // "who is Tommy?" (never saved as a Person) into
            // the generic pipeline with full graph context,
            // which answered "Tommy is your brother". Only
            // fires when NOTHING resolved, so a question about
            // a real person is never diverted here.
            if mentionedPeople.isEmpty,
               let candidate = WhoIsQuestionDetector.candidateName(in: query) {
                // Two very different answers hide behind "not in
                // People": the name is unknown, or it's been
                // journaled about and simply never added. The
                // second is answerable from the graph's own
                // unresolved-mention nodes, deterministically.
                let snapshot = graphSnapshots.first?.graph ?? .empty
                if let mention = UnresolvedPersonFinder.find(
                    name: candidate, in: snapshot
                ) {
                    await viewModel.answerDirectly(
                        requestID: request.id, text: mention.answerText
                    )
                } else {
                    await viewModel.askWhoIs(
                        requestID: request.id, question: query, people: []
                    )
                }
                return
            }

            // A question can name someone the app has never
            // heard of while asking about something else
            // entirely ("did Nora's birthday happen last
            // week"). Handing that to the model let it answer
            // from the nearest similar fact — it took Akhil's
            // birthday and put Nora's name on it. Refuse
            // deterministically instead.
            if let refusal = UnknownPersonGuard.refusal(
                for: query, people: people,
                graph: graphSnapshots.first?.graph ?? .empty
            ) {
                await viewModel.answerDirectly(
                    requestID: request.id, text: refusal
                )
                return
            }

            // Resolved here rather than inside the graph
            // retriever alone, because its time window has to
            // gate BOTH context paths. QueryIntentDraft has no
            // time dimension at all, so a purely temporal
            // question ("what did I do last week") is
            // unstructured as far as the lists below are
            // concerned, and semantic similarity cannot tell
            // July from August.
            let memoryIntent = MemoryQueryResolver.resolve(
                query: query, people: people,
                relationships: relationships, now: .now
            )
            let window = memoryIntent.timeRange
            let experiences = TimeWindowFilter.within(
                experiences, window: window, date: \.timelineDate)
            let decisions = TimeWindowFilter.within(
                decisions, window: window, date: \.timelineDate)
            let events = TimeWindowFilter.within(
                events, window: window, date: \.date)
            let reminders = TimeWindowFilter.within(
                reminders, window: window, date: \.createdAt)

            // Deterministic, guaranteed-correct matches for
            // whatever structure was found (e.g. "3 unpleasant
            // experiences recently") — empty when the question
            // has no such structure.
            let structuredExperiences = intent.hasStructure
                ? StructuredQueryRetriever.matchedExperiences(intent: intent, among: experiences)
                : []
            let structuredDecisions = intent.hasStructure
                ? StructuredQueryRetriever.matchedDecisions(intent: intent, among: decisions)
                : []
            let structuredEvents = intent.hasStructure
                ? StructuredQueryRetriever.matchedEvents(intent: intent, among: events)
                : []

            // Retrieve the entries most relevant to the question
            // (semantic), not just the most recent.
            let relevantExperiences = SemanticRetriever.topK(
                experiences, query: query, k: 10,
                text: EmbeddingService.experienceText, embedding: { $0.embedding }
            )
            let relevantDecisions = SemanticRetriever.topK(
                decisions, query: query, k: 8,
                text: EmbeddingService.decisionText, embedding: { $0.embedding }
            )
            let relevantReminders = SemanticRetriever.topK(
                reminders, query: query, k: 6,
                text: EmbeddingService.reminderText, embedding: { $0.embedding }
            )
            let relevantEvents = SemanticRetriever.topK(
                events, query: query, k: 6,
                text: EmbeddingService.eventText, embedding: { $0.embedding }
            )

            // Structured matches lead (they're the definitive
            // answer to the question's specific filter), then
            // semantic hits fill in general context, deduped.
            let mergedExperiences = mergeUnique(structuredExperiences, relevantExperiences, id: \.id)
            let mergedDecisions = mergeUnique(structuredDecisions, relevantDecisions, id: \.id)
            let mergedEvents = mergeUnique(structuredEvents, relevantEvents, id: \.id)

            let decisionSummaries = mergedDecisions.map(DecisionSummary.init)
            let experienceSummaries = mergedExperiences.map(ExperienceSummary.init)
            let reminderSummaries = relevantReminders.map(ReminderSummary.init)
            let eventSummaries = mergedEvents.map(EventSummary.init)
            let graph = graphSnapshots.first?.graph ?? .empty
            let graphResult = MemoryGraphRetriever.retrieve(
                intent: memoryIntent,
                graph: graph,
                now: .now,
                limit: 24
            )
            let packed = MemoryGraphContextPacker.packWithManifest(graphResult)

            await viewModel.ask(
                requestID: request.id, question: query,
                decisions: decisionSummaries, experiences: experienceSummaries,
                reminders: reminderSummaries, events: eventSummaries,
                people: peopleSummaries, graphContext: packed.text,
                // nil keeps the plain-prose path; non-nil routes
                // through the grounded, citation-checked one.
                packedContext: AdviceGroundingSettings.isEnabled ? packed : nil
            )
        }
    }

    /// The weather icon the Journal uses for an entry of that mood, or a plain
    /// bullet when the sentence carries no feeling. Stating a date is not an
    /// emotion, and marking it as one would be the app inventing a reading.
    @ViewBuilder
    private func sentenceMark(for sentence: String) -> some View {
        if let tone = SentenceToneDetector.tone(of: sentence) {
            Image(systemName: tone.symbol)
                .font(.footnote)
                .foregroundStyle(tone.tint)
                .frame(width: 18)
                .accessibilityLabel(tone.label)
        } else {
            Text("•")
                .foregroundStyle(AlbumTheme.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
        }
    }

    /// Example questions the user can tap, rather than read.
    ///
    /// "What do I even ask it?" is the hardest moment on this screen, and the
    /// old version answered it with two examples set in quotation marks that
    /// could not be acted on — the reader had to retype them. These fill the
    /// field, which also demonstrates the shape of a question that works here.
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRY ASKING")
                .font(.caption.weight(.medium))
                .tracking(1.6)
                .foregroundStyle(AlbumTheme.secondary)

            ForEach(Self.starterQuestions, id: \.self) { question in
                Button {
                    viewModel.question = question
                } label: {
                    HStack(spacing: 10) {
                        AlbumIconTile(symbol: "sparkle", size: 28)
                        Text(question)
                            .font(.callout)
                            .foregroundStyle(AlbumTheme.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AlbumTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(AlbumTheme.rule, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let starterQuestions = [
        "How do I usually handle money decisions?",
        "What helps me have a good day?",
        "Who have I been spending time with lately?"
    ]

    /// What the answers are drawn from.
    ///
    /// This was a caption at the bottom, which buried the app's whole claim:
    /// answers come from your own writing and nothing else. Shown as counts it
    /// also grows visibly as the journal does, which the sentence never did.
    private var groundedFooter: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                corpusStat(decisions.count, "decisions")
                corpusStat(experiences.count, "experiences")
                corpusStat(events.count, "events")
            }
            Label("Answers come from your own words", systemImage: "lock")
                .font(.caption2)
                .foregroundStyle(AlbumTheme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func corpusStat(_ count: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(AlbumTheme.heading(.title2))
                .foregroundStyle(AlbumTheme.dateAccent)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AlbumTheme.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            if decisions.isEmpty && experiences.isEmpty {
                hint("Save a few decisions or experiences first — answers draw on your history.")
            } else {
                suggestions
            }
        case .thinking:
            ProgressView("Thinking…")
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        case .answer(let text):
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("From your journal", systemImage: "book")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        speaker.toggle(text.withReadableDates.strippedMarkdown)
                    } label: {
                        Image(systemName: speaker.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                    }
                    .accessibilityLabel(speaker.isSpeaking ? "Stop reading" : "Read aloud")

                    Button {
                        // Stop any read-aloud first, otherwise the voice carries
                        // on describing an answer that is no longer on screen.
                        speaker.stop()
                        withAnimation(.snappy(duration: 0.2)) { viewModel.dismissAnswer() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AlbumTheme.secondary)
                    }
                    .accessibilityLabel("Dismiss answer")
                }
                // One line per sentence, each marked with the feeling in it.
                // An answer that names three days in one paragraph is a wall to
                // read back; separated and marked, the good days and the hard
                // ones can be told apart without reading every word.
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(text.withReadableDates.sentences.enumerated()), id: \.offset) { _, sentence in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            sentenceMark(for: sentence)
                            Text(sentence.renderedMarkdown)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .font(.body)
                .lineSpacing(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                #if DEBUG
                if let report = viewModel.debugGroundingReport {
                    groundingBadge(report)
                }
                if let debugContext = viewModel.debugContext {
                    DisclosureGroup("Debug: Context sent to model") {
                        Text(debugContext)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                }
                #endif
            }
            .padding()
            .background(AlbumTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toggleMic() {
        isQuestionFocused = false
        if viewModel.speech.isRecording {
            // Stop and let go. Copying the transcript here reads it a second
            // before the tail of the speech lands, and the transcript observer
            // is already the thing that keeps this field current — including
            // through the tail, which is what isTranscribing covers.
            viewModel.speech.stopRecording()
        } else {
            Task {
                if await viewModel.speech.requestAuthorization() {
                    viewModel.beginDictation()
                    try? await viewModel.speech.startRecording()
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Combines the structured (definitive) and semantic (general-context)
    /// matches, keeping `primary`'s order and dropping anything from
    /// `secondary` already present.
    private func mergeUnique<T, ID: Hashable>(_ primary: [T], _ secondary: [T], id: (T) -> ID) -> [T] {
        var seen = Set<ID>()
        var result: [T] = []
        for item in primary + secondary {
            let key = id(item)
            if seen.insert(key).inserted { result.append(item) }
        }
        return result
    }

    #if DEBUG
    /// Surfaces what GroundingValidator found for the last answer. Green means
    /// every citation resolved to something the model was actually shown — not
    /// that the answer is correct, since a real citation can still be
    /// misdescribed.
    @ViewBuilder
    private func groundingBadge(_ report: GroundingReport) -> some View {
        let ok = !report.hasFindings
        VStack(alignment: .leading, spacing: 4) {
            Label(
                ok ? "Grounded — all citations resolve" : "Grounding findings",
                systemImage: ok ? "checkmark.seal" : "exclamationmark.triangle"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(ok ? .green : .orange)

            if !report.unknownEvidence.isEmpty {
                Text("Cited evidence not in context: \(report.unknownEvidence.map(String.init).joined(separator: ", "))")
            }
            if !report.unknownPeople.isEmpty {
                Text("People not in context: \(report.unknownPeople.joined(separator: ", "))")
            }
            if !report.unknownDates.isEmpty {
                Text("Dates not in context: \(report.unknownDates.joined(separator: ", "))")
            }
            if report.citesNothing {
                Text("Named people or dates but cited no evidence — unverifiable.")
            }
        }
        .font(.caption2)
        .foregroundStyle(ok ? .secondary : .primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif
}
