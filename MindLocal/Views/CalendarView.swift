import SwiftUI
import SwiftData

/// The app's home: a unified chronological timeline of events, decisions, and
/// experiences. The "+" is the main entry point to add any of them.
struct CalendarView: View {
    @Query private var events: [Event]
    @Query private var decisions: [Decision]
    @Query private var experiences: [Experience]
    @Environment(\.modelContext) private var modelContext
    @State private var addSheet: AddSheet?
    @State private var showingSettings = false
    @State private var importMessage: String?
    private let calendarImporter = CalendarImportService()

    private var allItems: [TimelineItem] {
        // Decisions extracted from an experience appear inside that experience,
        // not as separate timeline items — only standalone decisions show here.
        var items: [TimelineItem] = events.map(TimelineItem.event)
        items += decisions.filter { $0.experience == nil }.map(TimelineItem.decision)
        items += experiences.map(TimelineItem.experience)
        return items
    }
    private var upcoming: [TimelineItem] {
        allItems.filter { $0.date > .now }.sorted { $0.date < $1.date }
    }
    private var past: [TimelineItem] {
        allItems.filter { $0.date <= .now }.sorted { $0.date > $1.date }
    }
    /// Past items grouped by calendar day, newest day first (items within a day
    /// stay newest-first from `past`).
    private var pastByDay: [(day: Date, items: [TimelineItem])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: past) { cal.startOfDay(for: $0.date) }
        return groups.map { (day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            List {
                if !upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcoming) { row($0) }
                            .onDelete { delete($0, from: upcoming) }
                    }
                }
                ForEach(pastByDay, id: \.day) { group in
                    Section(dayLabel(group.day)) {
                        ForEach(group.items) { row($0) }
                            .onDelete { delete($0, from: group.items) }
                    }
                }
            }
            .overlay {
                if allItems.isEmpty {
                    ContentUnavailableView(
                        "Nothing Yet",
                        systemImage: "calendar",
                        description: Text("Tap + to add an entry or an event.")
                    )
                }
            }
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { addSheet = .conversation } label: { Label("Talk about my day", systemImage: "moon.stars") }
                        Button { addSheet = .entry } label: { Label("New Entry", systemImage: "square.and.pencil") }
                        Button { addSheet = .event } label: { Label("New Event", systemImage: "calendar.badge.plus") }
                        Divider()
                        Button { Task { await importCalendar() } } label: {
                            Label("Import from Calendar", systemImage: "calendar.badge.clock")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                }
            }
            .alert("Calendar", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                Button("OK") { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
            .task { await calendarImporter.importIfAuthorized(into: modelContext) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(item: $addSheet) { sheet in
                switch sheet {
                case .conversation: JournalConversationView()
                case .entry: CaptureView()
                case .event: EventFormView { modelContext.insert($0) }
                }
            }
        }
    }

    private func importCalendar() async {
        switch await calendarImporter.importUpcoming(into: modelContext) {
        case .denied:
            importMessage = "MindLocal needs Calendar access. Enable it in Settings › MindLocal."
        case .imported(let new, let updated):
            if new == 0 && updated == 0 {
                importMessage = "No upcoming events found in your calendar."
            } else {
                importMessage = "Imported \(new) new event\(new == 1 ? "" : "s")\(updated > 0 ? ", updated \(updated)" : "")."
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if cal.component(.year, from: date) != cal.component(.year, from: .now) {
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func row(_ item: TimelineItem) -> some View {
        NavigationLink {
            destination(for: item)
        } label: {
            TimelineRow(item: item)
        }
    }

    @ViewBuilder
    private func destination(for item: TimelineItem) -> some View {
        switch item {
        case .event(let event):           EventDetailView(event: event)
        case .decision(let decision):      DecisionDetailView(decision: decision)
        case .experience(let experience):  ExperienceDetailView(experience: experience)
        }
    }

    private func delete(_ offsets: IndexSet, from list: [TimelineItem]) {
        for index in offsets where list.indices.contains(index) {
            switch list[index] {
            case .event(let e):      modelContext.delete(e)
            case .decision(let d):   modelContext.delete(d)
            case .experience(let x): modelContext.delete(x)
            }
        }
    }

    enum AddSheet: String, Identifiable {
        case conversation, entry, event
        var id: String { rawValue }
    }
}

/// A single timeline entry — event, decision, or experience.
enum TimelineItem: Identifiable {
    case event(Event)
    case decision(Decision)
    case experience(Experience)

    var id: String {
        switch self {
        case .event(let e):      "event-\(e.id)"
        case .decision(let d):   "decision-\(d.id)"
        case .experience(let x): "experience-\(x.id)"
        }
    }

    var date: Date {
        switch self {
        case .event(let e):      e.date
        case .decision(let d):   d.timelineDate
        case .experience(let x): x.timelineDate
        }
    }

    var title: String {
        switch self {
        case .event(let e):      e.title
        case .decision(let d):   d.title
        case .experience(let x): x.title
        }
    }

    var kind: String {
        switch self {
        case .event:      "Event"
        case .decision:   "Decision"
        case .experience: "Experience"
        }
    }

    var icon: String {
        switch self {
        case .event:            "calendar"
        case .decision:         "checklist"
        case .experience(let x): x.tone.symbol
        }
    }

    var tint: Color {
        switch self {
        case .event:      .blue
        case .decision:   .indigo
        case .experience(let x): x.tone == .pleasant ? .yellow : x.tone == .unpleasant ? .purple : .orange
        }
    }
}

private struct TimelineRow: View {
    let item: TimelineItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .foregroundStyle(item.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.kind)
                    Text("·")
                    Text(item.date, format: .dateTime.month().day().year())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Add-event sheet.
struct EventFormView: View {
    let onSave: (Event) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var date = Date.now
    @State private var domain: Domain = .other
    @State private var notes = ""
    @State private var location = ""
    @State private var isOutdoor = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("What is it? e.g. Meeting with financial advisor", text: $title)
                    DatePicker("When", selection: $date)
                    Picker("Domain", selection: $domain) {
                        ForEach(Domain.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                }
                Section {
                    Toggle("Outdoor event", isOn: $isOutdoor)
                    TextField("Location (city or address)", text: $location)
                } footer: {
                    Text("For outdoor events with a location, advice factors in the weather forecast.")
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(Event(title: title, notes: notes, date: date,
                                     location: location, isOutdoor: isOutdoor, domain: domain))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
