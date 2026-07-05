import SwiftUI
import SwiftData

/// Calendar of upcoming (and past) events, each with proactive, history-grounded
/// advice generated when you open it.
struct CalendarView: View {
    @Query(sort: \Event.date, order: .forward) private var events: [Event]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAdd = false

    private var upcoming: [Event] { events.filter { $0.date >= startOfToday } }
    private var past: [Event] { events.filter { $0.date < startOfToday }.reversed() }
    private var startOfToday: Date { Calendar.current.startOfDay(for: .now) }

    var body: some View {
        NavigationStack {
            List {
                if !upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcoming) { event in link(event) }
                            .onDelete { delete($0, from: upcoming) }
                    }
                }
                if !past.isEmpty {
                    Section("Past") {
                        ForEach(past) { event in link(event) }
                            .onDelete { delete($0, from: past) }
                    }
                }
            }
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView(
                        "No Events Yet",
                        systemImage: "calendar",
                        description: Text("Add an event and get advice grounded in your past decisions and experiences.")
                    )
                }
            }
            .navigationTitle("Calendar")
            .toolbar {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Event")
            }
            .navigationDestination(for: UUID.self) { id in
                if let event = events.first(where: { $0.id == id }) {
                    EventDetailView(event: event)
                }
            }
            .sheet(isPresented: $showingAdd) {
                EventFormView { event in modelContext.insert(event) }
            }
        }
    }

    private func link(_ event: Event) -> some View {
        NavigationLink(value: event.id) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline)
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                    Text(event.date, format: .dateTime.month().day().hour().minute())
                    Text("·")
                    Text(event.domain.label)
                    if event.generatedAdvice != nil {
                        Image(systemName: "sparkles").foregroundStyle(.purple)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private func delete(_ offsets: IndexSet, from list: [Event]) {
        for index in offsets where list.indices.contains(index) {
            modelContext.delete(list[index])
        }
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
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(Event(title: title, notes: notes, date: date, domain: domain))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
