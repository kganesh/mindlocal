import SwiftUI
import SwiftData

struct DecisionListView: View {
    @Query(sort: \Decision.createdAt, order: .reverse) private var decisions: [Decision]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var domainFilter: Domain?

    private var filtered: [Decision] {
        decisions.filter { d in
            (domainFilter == nil || d.domain == domainFilter)
            && (searchText.isEmpty
                || d.title.localizedCaseInsensitiveContains(searchText)
                || d.statement.localizedCaseInsensitiveContains(searchText)
                || d.rationale.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { decision in
                    NavigationLink(value: decision.id) {
                        DecisionRow(decision: decision)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { modelContext.delete(filtered[i]) }
                }
            }
            .overlay {
                if decisions.isEmpty {
                    ContentUnavailableView(
                        "No Decisions Yet",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Capture your first decision from the Capture tab.")
                    )
                }
            }
            .searchable(text: $searchText, prompt: "Search decisions")
            .toolbar {
                Menu {
                    Button("All Domains") { domainFilter = nil }
                    ForEach(Domain.allCases) { d in
                        Button(d.label) { domainFilter = d }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            .navigationTitle("Decisions")
            .navigationDestination(for: UUID.self) { id in
                if let decision = decisions.first(where: { $0.id == id }) {
                    DecisionDetailView(decision: decision)
                }
            }
        }
    }
}

struct DecisionRow: View {
    let decision: Decision

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(decision.title).font(.headline)
            Text(decision.statement).font(.subheadline).lineLimit(2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(decision.domain.label)
                Text("·")
                Text(decision.stakes.label + " stakes")
                Text("·")
                Text(decision.createdAt, style: .date)
                if decision.outcome != nil {
                    Image(systemName: "checkmark.seal").foregroundStyle(.green)
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
