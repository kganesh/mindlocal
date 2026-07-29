import SwiftUI
import SwiftData

/// The visual of a single diary page — warm paper, a dated header, and the
/// narrative set in handwriting. Used both standalone (DiaryPageView) and as a
/// page inside the flip-through reader (JournalReaderView).
struct DiaryPageContent: View {
    @Bindable var experience: Experience
    @Query(sort: \Person.name) private var allPeople: [Person]
    @State private var showingPeopleMap = false

    private let paper = Color(red: 0.98, green: 0.96, blue: 0.89)
    private let ink   = Color(red: 0.20, green: 0.16, blue: 0.12)
    private let noteBackground = Color(red: 0.92, green: 0.86, blue: 0.70).opacity(0.35)

    /// The narrative to read — the original note if we have it, else the summary.
    private var bodyText: String {
        let raw = experience.rawText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? experience.summary : raw
    }

    private var hasEnrichment: Bool {
        !experience.linkedPeople.isEmpty
            || !experience.activities.isEmpty
            || !experience.outcomes.isEmpty
            || !experience.hopes.isEmpty
            || !experience.decisions.isEmpty
            || !experience.reminders.isEmpty
            || !experience.conflicts.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(experience.timelineDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.custom("Caveat-Bold", size: 26))
                    .foregroundStyle(ink.opacity(0.65))

                if experience.hasLocation {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(experience.location)
                    }
                    .font(.custom("Caveat-Regular", size: 20))
                    .foregroundStyle(ink.opacity(0.55))
                }

                Rectangle()
                    .fill(ink.opacity(0.15))
                    .frame(height: 1)

                EnrichedDiaryBody(
                    text: bodyText,
                    linkedPeople: experience.linkedPeople,
                    allPeople: allPeople,
                    ink: ink
                )

                if !experience.learning.isEmpty {
                    Text("- \(experience.learning)")
                        .font(.custom("Caveat-Bold", size: 26))
                        .foregroundStyle(ink.opacity(0.8))
                        .padding(.top, 4)
                }

                HStack(spacing: 6) {
                    Image(systemName: experience.tone.symbol)
                    Text(experience.tone.label)
                }
                .font(.custom("Caveat-Regular", size: 22))
                .foregroundStyle(experience.tone.tint)
                .padding(.top, 6)

                if experience.hasHealthContext {
                    HStack(spacing: 16) {
                        if let hours = experience.sleepHours {
                            healthChip("bed.double.fill", String(format: "%.1f h", hours))
                        }
                        if let steps = experience.steps {
                            healthChip("figure.walk", steps.formatted())
                        }
                        if let count = experience.workoutCount, count > 0 {
                            healthChip("figure.run", count == 1 ? "1 workout" : "\(count) workouts")
                        }
                    }
                    .font(.custom("Caveat-Regular", size: 18))
                    .foregroundStyle(ink.opacity(0.5))
                }

                if hasEnrichment {
                    enrichmentNotes
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 480, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(paper)
    }

    private func healthChip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text)
        }
    }

    private var enrichmentNotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("MindLocal noticed", systemImage: "sparkles")
                .font(.custom("Caveat-Bold", size: 24))
                .foregroundStyle(ink.opacity(0.72))

            if !experience.linkedPeople.isEmpty {
                enrichmentGroup("People", systemImage: "person.2") {
                    ForEach(experience.linkedPeople) { person in
                        NavigationLink {
                            PersonDetailView(person: person)
                        } label: {
                            Label(person.displayName(among: allPeople), systemImage: "person.crop.circle")
                        }
                    }
                    Button {
                        showingPeopleMap = true
                    } label: {
                        Label("People Map", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                }
            }

            if !experience.activities.isEmpty {
                enrichmentGroup("Activities", systemImage: "figure.walk") {
                    ForEach(cleaned(experience.activities), id: \.self) { Text($0) }
                }
            }

            if !experience.outcomes.isEmpty {
                enrichmentGroup("Outcomes", systemImage: "arrow.right.circle") {
                    ForEach(cleaned(experience.outcomes), id: \.self) { Text($0) }
                }
            }

            if !experience.hopes.isEmpty {
                enrichmentGroup("Hopes", systemImage: "sparkles") {
                    ForEach(cleaned(experience.hopes), id: \.self) { Text($0) }
                }
            }

            if !experience.decisions.isEmpty {
                enrichmentGroup("Decisions", systemImage: "checklist") {
                    ForEach(experience.decisions) { decision in
                        NavigationLink {
                            DecisionDetailView(decision: decision)
                        } label: {
                            Text(decision.title)
                        }
                    }
                }
            }

            if !experience.reminders.isEmpty {
                enrichmentGroup("Reminders", systemImage: "bell.badge") {
                    ForEach(experience.reminders) { reminder in
                        HStack(spacing: 5) {
                            Image(systemName: reminder.isDone ? "checkmark.circle.fill" : "circle")
                            Text(reminder.text)
                        }
                    }
                }
            }

            if !experience.conflicts.isEmpty {
                enrichmentGroup("Conflicts", systemImage: "person.crop.circle.badge.exclamationmark") {
                    ForEach(experience.conflicts) { conflict in
                        HStack(spacing: 5) {
                            Image(systemName: conflict.resolution.symbol)
                            Text(conflict.summary.isEmpty ? "Disagreement" : conflict.summary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(noteBackground, in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 8)
        .sheet(isPresented: $showingPeopleMap) {
            PeopleGraphSheet(focusName: diaryMapFocusName)
        }
    }

    private var diaryMapFocusName: String? {
        guard experience.linkedPeople.count == 1, let person = experience.linkedPeople.first else { return nil }
        return person.fullDisplayName
    }

    private func enrichmentGroup<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink.opacity(0.58))
            FlowTagLayout {
                content()
            }
            .font(.callout)
            .foregroundStyle(ink.opacity(0.78))
            .buttonStyle(.plain)
        }
    }

    private func cleaned(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// Handwritten diary text that turns resolved person names into tappable links
/// after extraction has linked the entry to graph nodes.
private struct EnrichedDiaryBody: View {
    let text: String
    let linkedPeople: [Person]
    let allPeople: [Person]
    let ink: Color

    private var paragraphs: [String] {
        text.components(separatedBy: .newlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                if paragraph.isEmpty {
                    Color.clear.frame(height: 10)
                } else {
                    FlowTagLayout(horizontalSpacing: 0, verticalSpacing: 4) {
                        ForEach(segments(in: paragraph)) { segment in
                            switch segment.kind {
                            case .plain:
                                Text(segment.text)
                                    .foregroundStyle(ink)
                            case .person(let person):
                                NavigationLink {
                                    PersonDetailView(person: person)
                                } label: {
                                    Text(segment.text)
                                        .foregroundStyle(Color.accentColor)
                                        .underline(true, color: Color.accentColor.opacity(0.45))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(person.displayName(among: allPeople))
                            }
                        }
                    }
                }
            }
        }
        .font(.custom("Caveat-Regular", size: 30))
        .lineSpacing(6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var matchCandidates: [PersonMatchCandidate] {
        var seen = Set<String>()
        var candidates: [PersonMatchCandidate] = []
        for person in linkedPeople {
            for name in person.normalizedNames {
                let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty, seen.insert("\(person.id)-\(normalized)").inserted else { continue }
                candidates.append(PersonMatchCandidate(person: person, phrase: normalized))
            }
        }
        return candidates.sorted {
            if $0.phrase.count == $1.phrase.count {
                return $0.phrase < $1.phrase
            }
            return $0.phrase.count > $1.phrase.count
        }
    }

    private func segments(in paragraph: String) -> [DiaryTextSegment] {
        let candidates = matchCandidates
        var result: [DiaryTextSegment] = []
        var plainStart = paragraph.startIndex
        var current = paragraph.startIndex

        while current < paragraph.endIndex {
            if let match = firstMatch(in: paragraph, at: current, candidates: candidates) {
                if plainStart < current {
                    result.append(DiaryTextSegment(text: String(paragraph[plainStart..<current]), kind: .plain))
                }
                result.append(DiaryTextSegment(text: String(paragraph[current..<match.end]), kind: .person(match.person)))
                current = match.end
                plainStart = current
            } else {
                current = paragraph.index(after: current)
            }
        }
        if plainStart < paragraph.endIndex {
            result.append(DiaryTextSegment(text: String(paragraph[plainStart..<paragraph.endIndex]), kind: .plain))
        }
        return result
    }

    private func firstMatch(
        in paragraph: String,
        at start: String.Index,
        candidates: [PersonMatchCandidate]
    ) -> (person: Person, end: String.Index)? {
        guard isBoundaryBefore(start, in: paragraph) else { return nil }
        for candidate in candidates {
            guard let end = paragraph.index(start, offsetBy: candidate.phrase.count, limitedBy: paragraph.endIndex) else {
                continue
            }
            guard isBoundaryAfter(end, in: paragraph) else { continue }
            if String(paragraph[start..<end]).lowercased() == candidate.phrase {
                return (candidate.person, end)
            }
        }
        return nil
    }

    private func isBoundaryBefore(_ index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        let previous = text[text.index(before: index)]
        return !isNameCharacter(previous)
    }

    private func isBoundaryAfter(_ index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex else { return true }
        return !isNameCharacter(text[index])
    }

    private func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "'"
    }
}

private struct PersonMatchCandidate {
    let person: Person
    let phrase: String
}

private struct DiaryTextSegment: Identifiable {
    let id = UUID()
    let text: String
    let kind: Kind

    enum Kind {
        case plain
        case person(Person)
    }
}

/// A compact wrapping layout for handwritten tokens and extraction chips.
private struct FlowTagLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        let rows = rows(for: subviews, maxWidth: maxWidth)
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height
        } + CGFloat(max(rows.count - 1, 0)) * verticalSpacing
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [FlowRow] {
        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let spacing = currentItems.isEmpty ? CGFloat.zero : horizontalSpacing
            if !currentItems.isEmpty, currentWidth + spacing + size.width > maxWidth {
                rows.append(FlowRow(items: currentItems, height: currentHeight))
                currentItems = []
                currentWidth = 0
                currentHeight = 0
            }
            currentItems.append(FlowItem(index: index, size: size))
            currentWidth += (currentItems.count == 1 ? 0 : horizontalSpacing) + size.width
            currentHeight = max(currentHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, height: currentHeight))
        }
        return rows
    }

    private struct FlowRow {
        let items: [FlowItem]
        let height: CGFloat
    }

    private struct FlowItem {
        let index: Int
        let size: CGSize
    }
}

/// Reads a single journal entry as a diary page. Edit opens the structured editor.
struct DiaryPageView: View {
    @Bindable var experience: Experience

    var body: some View {
        DiaryPageContent(experience: experience)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(experience.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ExperienceDetailView(experience: experience)
                    } label: {
                        Text("Edit")
                    }
                }
            }
    }
}
