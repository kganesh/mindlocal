import SwiftUI
import SwiftData

struct ExperienceListView: View {
    @Query(sort: \Experience.createdAt, order: .reverse) private var experiences: [Experience]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var toneFilter: ExperienceTone?

    private var filtered: [Experience] {
        experiences.filter { e in
            (toneFilter == nil || e.tone == toneFilter)
            && (searchText.isEmpty
                || e.title.localizedCaseInsensitiveContains(searchText)
                || e.summary.localizedCaseInsensitiveContains(searchText)
                || e.learning.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { experience in
                    NavigationLink(value: experience.id) {
                        ExperienceRow(experience: experience)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { modelContext.delete(filtered[i]) }
                }
            }
            .overlay {
                if experiences.isEmpty {
                    ContentUnavailableView(
                        "No Experiences Yet",
                        systemImage: "sparkle",
                        description: Text("Capture one from the Capture tab — switch to Experience.")
                    )
                }
            }
            .searchable(text: $searchText, prompt: "Search experiences")
            .toolbar {
                Menu {
                    Button("All") { toneFilter = nil }
                    ForEach(ExperienceTone.allCases) { tone in
                        Button(tone.label) { toneFilter = tone }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            .navigationTitle("Experiences")
            .navigationDestination(for: UUID.self) { id in
                if let experience = experiences.first(where: { $0.id == id }) {
                    ExperienceDetailView(experience: experience)
                }
            }
        }
    }
}

struct ExperienceRow: View {
    let experience: Experience

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: experience.tone.symbol)
                    .foregroundStyle(experience.tone == .pleasant ? .yellow
                                     : experience.tone == .unpleasant ? .indigo : .orange)
                Text(experience.title).font(.headline)
            }
            Text(experience.summary).font(.subheadline).lineLimit(2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(experience.tone.label)
                Text("·")
                Text(experience.domain.label)
                Text("·")
                Text(experience.createdAt, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
