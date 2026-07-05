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

    private var allItems: [TimelineItem] {
        events.map(TimelineItem.event)
        + decisions.map(TimelineItem.decision)
        + experiences.map(TimelineItem.experience)
    }
    private var upcoming: [TimelineItem] {
        allItems.filter { $0.date > .now }.sorted { $0.date < $1.date }
    }
    private var past: [TimelineItem] {
        allItems.filter { $0.date <= .now }.sorted { $0.date > $1.date }
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
                if !past.isEmpty {
                    Section("Timeline") {
                        ForEach(past) { row($0) }
                            .onDelete { delete($0, from: past) }
                    }
                }
            }
            .overlay {
                if allItems.isEmpty {
                    ContentUnavailableView(
                        "Nothing Yet",
                        systemImage: "calendar",
                        description: Text("Tap + to add an event, decision, or experience.")
                    )
                }
            }
            .navigationTitle("Timeline")
            .toolbar {
                Menu {
                    Button { addSheet = .event } label: { Label("New Event", systemImage: "calendar.badge.plus") }
                    Button { addSheet = .decision } label: { Label("New Decision", systemImage: "checklist") }
                    Button { addSheet = .experience } label: { Label("New Experience", systemImage: "sparkle") }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add")
            }
            .sheet(item: $addSheet) { sheet in
                switch sheet {
                case .event:      EventFormView { modelContext.insert($0) }
                case .decision:   CaptureView(initialMode: .decision)
                case .experience: CaptureView(initialMode: .experience)
                }
            }
        }
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
        case event, decision, experience
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
