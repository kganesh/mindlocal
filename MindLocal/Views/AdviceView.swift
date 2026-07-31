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
    @State private var showingVoiceSettings = false
    @State private var showingHowIDecide = false
    @FocusState private var isQuestionFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Ask about a decision or experience…", text: $viewModel.question, axis: .vertical)
                            .lineLimit(1...4)
                            .padding(12)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                            .focused($isQuestionFocused)

                        Button {
                            toggleMic()
                        } label: {
                            Image(systemName: viewModel.speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(viewModel.speech.isRecording ? .red : .accentColor)
                        }
                        .accessibilityLabel(viewModel.speech.isRecording ? "Stop recording" : "Ask by voice")
                    }
                    // Stream the spoken question into the field while recording.
                    .onChange(of: viewModel.speech.transcript) { _, newValue in
                        if viewModel.speech.isRecording { viewModel.question = newValue }
                    }

                    Button {
                        isQuestionFocused = false
                        guard let request = viewModel.beginAsk() else { return }
                        let query = request.question
                        Task {
                            // What is this question asking FOR — a tone, topic,
                            // count, sort? Read once, up front, so both the
                            // structured and semantic passes can use it.
                            let intent = await viewModel.extractIntent(for: query)

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
                            // Anyone named in the question gets their actual
                            // People-graph profile included as ground truth, not
                            // just whatever text happens to rank as similar.
                            let mentionedPeople = PersonContextBuilder.mentionedPeople(in: query, among: people)
                            let peopleSummaries = mentionedPeople.map {
                                PersonProfileSummary(
                                    id: $0.id,
                                    text: PersonContextBuilder.profile(for: $0, relationships: relationships)
                                )
                            }
                            let graph = graphSnapshots.first?.graph ?? .empty
                            let graphResult = MemoryGraphRetriever.retrieve(
                                query: query,
                                graph: graph,
                                people: people,
                                relationships: relationships,
                                now: .now,
                                limit: 24
                            )
                            let graphContext = MemoryGraphContextPacker.pack(graphResult)

                            await viewModel.ask(
                                requestID: request.id, question: query,
                                decisions: decisionSummaries, experiences: experienceSummaries,
                                reminders: reminderSummaries, events: eventSummaries,
                                people: peopleSummaries, graphContext: graphContext
                            )
                        }
                    } label: {
                        Label("Ask", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canAsk)

                    content

                    Spacer(minLength: 0)

                    Text("Grounded in your \(decisions.count) decision\(decisions.count == 1 ? "" : "s"), \(experiences.count) experience\(experiences.count == 1 ? "" : "s"), \(reminders.count) reminder\(reminders.count == 1 ? "" : "s"), and \(events.count) event\(events.count == 1 ? "" : "s"). Runs on-device.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Advise")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingHowIDecide = true } label: {
                        Image(systemName: "brain.head.profile")
                    }
                    .accessibilityLabel("How I decide")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingVoiceSettings = true } label: {
                        Image(systemName: "waveform")
                    }
                    .accessibilityLabel("Read-aloud voice")
                }
            }
            .sheet(isPresented: $showingVoiceSettings) { VoiceSettingsView() }
            .sheet(isPresented: $showingHowIDecide) { HowIDecideView() }
            .onDisappear { speaker.stop() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            if decisions.isEmpty && experiences.isEmpty {
                hint("Save a few decisions or experiences first — answers draw on your history.")
            } else {
                hint("Try: \"How do I usually handle money decisions?\" or \"What helps me have a good day?\"")
            }
        case .thinking:
            ProgressView("Thinking…")
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        case .answer(let text):
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Answer", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        speaker.toggle(text.strippedMarkdown)
                    } label: {
                        Image(systemName: speaker.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                    }
                    .accessibilityLabel(speaker.isSpeaking ? "Stop reading" : "Read aloud")
                }
                Text(text.renderedMarkdown)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toggleMic() {
        isQuestionFocused = false
        if viewModel.speech.isRecording {
            viewModel.speech.stopRecording()
            viewModel.question = viewModel.speech.transcript
        } else {
            Task {
                if await viewModel.speech.requestAuthorization() {
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
}
