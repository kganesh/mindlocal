import SwiftUI

/// Swipe between entries while keeping the journal's navigation and data context.
struct JournalReaderView: View {
    let entries: [Experience]
    @State private var index: Int

    init(entries: [Experience], startIndex: Int) {
        self.entries = entries
        _index = State(initialValue: max(0, min(startIndex, entries.count - 1)))
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView("Nothing to read", systemImage: "book")
            } else {
                TabView(selection: $index) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                        DiaryPageContent(experience: entry).tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button { index -= 1 } label: {
                            Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                        }
                        .disabled(index == 0)
                        .accessibilityLabel("Newer entry")
                        Spacer()
                        Text("\(index + 1) of \(entries.count)")
                            .font(.caption)
                            .foregroundStyle(AlbumTheme.secondary)
                            .accessibilityLabel("Entry \(index + 1) of \(entries.count)")
                        Spacer()
                        Button { index += 1 } label: {
                            Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                        }
                        .disabled(index >= entries.count - 1)
                        .accessibilityLabel("Older entry")
                    }
                    .padding(.horizontal, 24)
                    .background(AlbumTheme.background)
                }
            }
        }
        .albumScreen()
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if entries.indices.contains(index) {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Edit") { ExperienceDetailView(experience: entries[index]) }
                }
            }
        }
    }
}
