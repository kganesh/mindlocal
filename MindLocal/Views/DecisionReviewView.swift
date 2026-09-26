import SwiftUI
import SwiftData

/// Surfaces decisions whose revisit date has arrived and asks — in one tap — how
/// they turned out. Closing this loop is what lets MindLocal learn what works for
/// you (domain-model.md, Phase 1).
struct DecisionReviewView: View {
    @Query(sort: \Decision.revisitAt) private var decisions: [Decision]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Quick-capture options (excludes "too early", which reschedules instead).
    private let quickResults: [OutcomeResult] = [.workedOut, .mixed, .regret]

    private var due: [Decision] {
        decisions.filter { $0.isDueForRevisit() }
    }

    var body: some View {
        NavigationStack {
            Group {
                if due.isEmpty {
                    ContentUnavailableView(
                        "All caught up",
                        systemImage: "checkmark.circle",
                        description: Text("No decisions to revisit right now. We'll ask again as they come due.")
                    )
                } else {
                    List {
                        Section {
                            AlbumHeading(title: "How did it turn out?", subtitle: "A moment to look back, in your own time.")
                                .listRowBackground(Color.clear)
                        }
                        ForEach(due) { decision in
                            Section {
                                card(for: decision)
                            }
                        }
                    }
                }
            }
            .albumScreen()
            .navigationTitle("Revisit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func card(for decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(decision.title).font(AlbumTheme.heading(.title3))
            if !decision.statement.isEmpty {
                Text(decision.statement)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Decided \(decision.timelineDate.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.tertiary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 10) {
                ForEach(quickResults) { result in
                    Button {
                        record(result, for: decision)
                    } label: {
                        Text(result.label)
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(tint(for: result))
                }
            }

            Button {
                reschedule(decision)
            } label: {
                Label("Too early — remind me later", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private func record(_ result: OutcomeResult, for decision: Decision) {
        decision.outcome = Outcome(result: result)
        try? modelContext.save()   // drops off `due` on the next query pass
    }

    /// Push the revisit date out so it resurfaces later, without recording a result.
    private func reschedule(_ decision: Decision) {
        decision.revisitAt = .now.addingTimeInterval(14 * 86_400)
        try? modelContext.save()
    }

    private func tint(for result: OutcomeResult) -> Color {
        switch result {
        case .workedOut: .green
        case .mixed:     .yellow
        case .regret:    .orange
        case .tooEarly:  .secondary
        }
    }
}
