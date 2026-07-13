import SwiftUI
import SwiftData

/// The visible "you-model": a mirror of how the user's decisions tend to turn
/// out, plus principles they curate. Everything is grounded in recorded outcomes
/// (domain-model.md, Phase 2) — a reflection, never a grade.
struct HowIDecideView: View {
    @Query private var decisions: [Decision]
    @Query(sort: \Principle.createdAt, order: .reverse) private var principles: [Principle]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var newPrinciple = ""

    private var overall: DecisionInsights.Tally { DecisionInsights.overall(decisions) }
    private var byDomain: [DecisionInsights.Group] { DecisionInsights.byDomain(decisions) }
    private var byValue: [DecisionInsights.Group] { DecisionInsights.byPrioritizedValue(decisions) }

    var body: some View {
        NavigationStack {
            List {
                if overall.total == 0 {
                    Section {
                        ContentUnavailableView(
                            "Not enough yet",
                            systemImage: "chart.bar.doc.horizontal",
                            description: Text("Record how a few decisions turned out — from the Timeline's “revisit” prompt — and your patterns will show up here.")
                        )
                    }
                } else {
                    Section {
                        scoreRow("Worked out", overall.workedOut, of: overall.decided, tint: .green)
                        scoreRow("Mixed", overall.mixed, of: overall.decided, tint: .yellow)
                        scoreRow("Regret", overall.regret, of: overall.decided, tint: .orange)
                    } header: {
                        Text("Your track record")
                    } footer: {
                        Text("Across \(overall.decided) decision\(overall.decided == 1 ? "" : "s") you've reflected on.")
                    }

                    if !byDomain.isEmpty {
                        Section("By area of life") {
                            ForEach(byDomain) { groupRow($0) }
                        }
                    }

                    if !byValue.isEmpty {
                        Section {
                            ForEach(byValue) { groupRow($0) }
                        } header: {
                            Text("When you prioritize…")
                        } footer: {
                            Text("How things turned out when you optimized for each value.")
                        }
                    }
                }

                Section {
                    ForEach(principles) { principle in
                        Text(principle.text)
                    }
                    .onDelete { offsets in
                        for i in offsets { modelContext.delete(principles[i]) }
                    }
                    HStack(alignment: .top) {
                        TextField("Add a principle you live by…", text: $newPrinciple, axis: .vertical)
                        Button(action: addPrinciple) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newPrinciple.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("My principles")
                } footer: {
                    Text("How you want to decide. MindLocal will draw on these when it advises you.")
                }
            }
            .navigationTitle("How I Decide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func addPrinciple() {
        let text = newPrinciple.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        modelContext.insert(Principle(text: text))
        newPrinciple = ""
    }

    private func scoreRow(_ label: String, _ count: Int, of total: Int, tint: Color) -> some View {
        HStack {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(label)
            Spacer()
            Text(total > 0 ? "\(count) · \(Int((Double(count) / Double(total)) * 100))%" : "\(count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func groupRow(_ group: DecisionInsights.Group) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(group.name).font(.subheadline.weight(.medium))
                Spacer()
                if let rate = group.tally.workedOutRate {
                    Text("\(Int(rate * 100))% worked out")
                        .font(.caption)
                        .foregroundStyle(rate >= 0.6 ? .green : rate <= 0.34 ? .orange : .secondary)
                }
            }
            Text(tallyLine(group.tally))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func tallyLine(_ t: DecisionInsights.Tally) -> String {
        var parts: [String] = []
        if t.workedOut > 0 { parts.append("\(t.workedOut) worked out") }
        if t.mixed > 0 { parts.append("\(t.mixed) mixed") }
        if t.regret > 0 { parts.append("\(t.regret) regret") }
        if t.tooEarly > 0 { parts.append("\(t.tooEarly) too early") }
        return parts.joined(separator: " · ")
    }
}
