import SwiftUI
import SwiftData

struct ExperienceListView: View {
    @Query(sort: \Experience.createdAt, order: .reverse) private var experiences: [Experience]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var toneFilter: ExperienceTone?
    @State private var showingTrends = false
    @State private var showingCapture = false

    private var filtered: [Experience] {
        experiences.filter { e in
            (toneFilter == nil || e.tone == toneFilter)
            && (searchText.isEmpty
                || e.title.localizedCaseInsensitiveContains(searchText)
                || e.summary.localizedCaseInsensitiveContains(searchText)
                || (e.rawText?.localizedCaseInsensitiveContains(searchText) ?? false)
                || e.learning.localizedCaseInsensitiveContains(searchText))
        }
        .sorted { $0.timelineDate > $1.timelineDate }
    }

    private var days: [Date] {
        Set(filtered.map { Calendar.current.startOfDay(for: $0.timelineDate) }).sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            List {
                AlbumHeading(title: "The days you keep.", subtitle: "Little moments, in your own words.")
                    .padding(.vertical, 16)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                if experiences.isEmpty {
                    ContentUnavailableView {
                        Label("Your story starts here", systemImage: "book.closed")
                    } description: {
                        Text("A thought, a conversation, a small part of your day. There’s room for all of it.")
                    } actions: {
                        Button("Write an entry") { showingCapture = true }
                            .buttonStyle(AlbumPrimaryButtonStyle())
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        Label("No matching moments", systemImage: "magnifyingglass")
                    } description: {
                        Text("Try another word or choose a different feeling.")
                    } actions: {
                        Button("Clear filters") { searchText = ""; toneFilter = nil }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(days, id: \.self) { day in
                        let entries = filtered.filter { Calendar.current.isDate($0.timelineDate, inSameDayAs: day) }
                        Section {
                            ForEach(entries) { experience in
                                NavigationLink(value: experience.id) {
                                    ExperienceRow(experience: experience)
                                }
                                .listRowBackground(Color.clear)
                            }
                            .onDelete { offsets in
                                for i in offsets { modelContext.delete(entries[i]) }
                            }
                        } header: {
                            Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AlbumTheme.dateAccent)
                                .textCase(nil)
                                .padding(.top, 12)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listRowSpacing(8)
            .albumScreen()
            .searchable(text: $searchText, prompt: "Find a memory")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingTrends = true } label: { Image(systemName: "chart.xyaxis.line") }
                        .accessibilityLabel("Mood trends")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button("All feelings") { toneFilter = nil }
                        ForEach(ExperienceTone.allCases) { tone in
                            Button(tone.label) { toneFilter = tone }
                        }
                    } label: {
                        Image(systemName: toneFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel(toneFilter.map { "Filter: \($0.label)" } ?? "Filter entries")
                    Button { showingCapture = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Write an entry")
                }
            }
            .sheet(isPresented: $showingTrends) { MoodTrendsView() }
            .sheet(isPresented: $showingCapture) { CaptureView() }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                let entries = filtered
                JournalReaderView(entries: entries, startIndex: entries.firstIndex(where: { $0.id == id }) ?? 0)
            }
        }
    }
}

struct ExperienceRow: View {
    let experience: Experience

    private var excerpt: String {
        let raw = experience.rawText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? experience.summary : raw
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(experience.title)
                .font(AlbumTheme.heading(.title3))
                .foregroundStyle(AlbumTheme.ink)
            Text(excerpt)
                .font(.subheadline)
                .lineSpacing(4)
                .lineLimit(3)
                .foregroundStyle(AlbumTheme.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { metadata }
                VStack(alignment: .leading, spacing: 8) { metadata }
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var metadata: some View {
        AlbumTag(title: experience.tone.label, symbol: experience.tone.symbol)
        Text(experience.kind.label)
            .font(.caption)
            .foregroundStyle(AlbumTheme.secondary)
    }
}
