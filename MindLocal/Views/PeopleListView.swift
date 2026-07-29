import SwiftUI
import SwiftData

/// How the People tab is presented: flat list, 2D graph, or 3D graph.
enum PeopleViewMode: String, CaseIterable, Identifiable {
    case list, graph2D, graph3D
    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: return "List"
        case .graph2D: return "Graph (2D)"
        case .graph3D: return "Graph (3D)"
        }
    }
    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .graph2D: return "point.3.connected.trianglepath.dotted"
        case .graph3D: return "move.3d"
        }
    }
}

/// Browse the people mentioned across entries — the filter-by-person surface.
struct PeopleListView: View {
    @Query(sort: \Person.name) private var people: [Person]
    @Environment(\.modelContext) private var modelContext
    @State private var mode: PeopleViewMode = .list

    var body: some View {
        NavigationStack {
            Group {
                if people.isEmpty {
                    ContentUnavailableView(
                        "No People Yet",
                        systemImage: "person.2",
                        description: Text("People you mention in your entries show up here.")
                    )
                } else {
                    switch mode {
                    case .list: listView
                    case .graph2D: PeopleGraphView()
                    case .graph3D: PeopleGraph3DView()
                    }
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("View", selection: $mode) {
                            ForEach(PeopleViewMode.allCases) { m in
                                Label(m.title, systemImage: m.systemImage).tag(m)
                            }
                        }
                    } label: {
                        Image(systemName: mode.systemImage)
                    }
                    .accessibilityLabel("Change view")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        modelContext.insert(Person(name: "New Person"))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add person")
                }
            }
            .onAppear { _ = Person.fetchOrCreateMe(in: modelContext) }
        }
    }

    private var listView: some View {
        List {
            ForEach(people) { person in
                NavigationLink {
                    PersonDetailView(person: person)
                } label: {
                    HStack {
                        Label(person.displayName(among: people), systemImage: person.isMe ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                        Spacer()
                        Text("\(person.experiences.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: !person.isMe) {
                    // Deleting "Me" nullifies every relationship edge that pointed
                    // at it (orphaned, not removed) and loses the whole kinship
                    // graph anchor — fetchOrCreateMe only rebuilds a blank node,
                    // it can't restore the edges. Never offer delete on this row.
                    if !person.isMe {
                        Button(role: .destructive) {
                            modelContext.delete(person)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

/// A person's entries (filter-by-person) plus lightweight editing of their names.
struct PersonDetailView: View {
    @Bindable var person: Person
    @Environment(\.modelContext) private var modelContext
    @Query private var allRelationships: [PersonRelationship]
    @Query private var allConflicts: [Conflict]
    @Query private var allReminders: [Reminder]
    @Query private var allEvents: [Event]
    @Query(sort: \Person.name) private var allPeople: [Person]
    @State private var addingRelationship = false
    @State private var mergingPerson = false
    @State private var showingPeopleMap = false
    @State private var newNickname = ""

    /// Whether another person shares this person's first name — the moment a
    /// distinguisher (last name or context) becomes worth adding.
    private var sharesFirstName: Bool {
        allPeople.contains { $0 !== person && $0.name.caseInsensitiveCompare(person.name) == .orderedSame }
    }

    private var entries: [Experience] {
        person.experiences.sorted { $0.timelineDate > $1.timelineDate }
    }

    private var trimmedNickname: String {
        newNickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Adds the typed nickname as an alias so future entries using it resolve to
    /// this person. Skips blanks and any spelling this person already answers to.
    private func addNickname() {
        let name = trimmedNickname
        guard !name.isEmpty, !person.matches(name) else { newNickname = ""; return }
        person.aliases.append(name)
        newNickname = ""
    }

    /// Edges touching this person, rendered from this person's perspective.
    private var relationships: [PersonRelationship] {
        allRelationships.filter { $0.subject === person || $0.object === person }
    }

    /// Conflicts recorded with this person, most recent first.
    private var conflicts: [Conflict] {
        allConflicts
            .filter { $0.withPerson === person }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Reminders about this person: open ones first (oldest first, so the
    /// longest-standing gets seen), done ones after.
    private var reminders: [Reminder] {
        allReminders
            .filter { $0.person === person }
            .sorted { a, b in
                if a.isDone != b.isDone { return !a.isDone }
                return a.createdAt < b.createdAt
            }
    }

    /// This person's upcoming scheduled events — a day a reminder notification
    /// will fire, if there are still open reminders by then.
    private var upcomingEvents: [Event] {
        allEvents
            .filter { $0.person === person && $0.date > .now }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        Form {
            Section {
                TextField("First name", text: $person.name)
                TextField("Last name (optional)", text: $person.lastName)
                TextField("Context — e.g. work, cousin (optional)", text: $person.qualifier)
                    .autocorrectionDisabled()
                if person.isMe {
                    Label("This is you", systemImage: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Name")
            } footer: {
                if sharesFirstName && person.distinguisher.isEmpty {
                    Label("Someone else is also named \(person.name). Add a last name or context to tell them apart.",
                          systemImage: "person.2.fill")
                }
            }
            Section {
                ForEach(person.aliases, id: \.self) { alias in
                    Text(alias)
                }
                .onDelete { person.aliases.remove(atOffsets: $0) }
                HStack {
                    TextField("Add a nickname", text: $newNickname)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .onSubmit(addNickname)
                    Button("Add", action: addNickname)
                        .disabled(trimmedNickname.isEmpty)
                }
            } header: {
                Text("Also called")
            } footer: {
                Text("Nicknames and other names for \(person.name). Future entries that use one will link to this person.")
            }
            Section("Relationships") {
                ForEach(relationships) { edge in
                    relationshipRow(edge)
                }
                .onDelete { offsets in
                    for i in offsets { modelContext.delete(relationships[i]) }
                }
                Button {
                    addingRelationship = true
                } label: {
                    Label("Add relationship", systemImage: "person.2.badge.plus")
                }
            }
            if !reminders.isEmpty {
                Section {
                    ForEach(reminders) { reminder in
                        Button {
                            reminder.isDone ? reminder.markNotDone() : reminder.markDone()
                            Task { await EventReminderNotificationService.rescheduleAll(for: person, events: allEvents) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: reminder.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(reminder.isDone ? Color.accentColor : .secondary)
                                Text(reminder.text)
                                    .strikethrough(reminder.isDone)
                                    .foregroundStyle(reminder.isDone ? .secondary : .primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    if !upcomingEvents.isEmpty, let next = upcomingEvents.first {
                        Text("These will be sent as a notification on \(next.date.formatted(date: .abbreviated, time: .omitted)) for \"\(next.title)\".")
                    } else {
                        Text("Tap to check off. Schedule an event with \(person.name) to also get a same-day notification.")
                    }
                }
            }
            if !conflicts.isEmpty {
                Section("Conflicts") {
                    ForEach(conflicts) { conflict in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(conflict.summary.isEmpty ? "Disagreement" : conflict.summary)
                                    .font(.subheadline)
                                Spacer()
                                Label(conflict.resolution.label, systemImage: conflict.resolution.symbol)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .labelStyle(.titleAndIcon)
                            }
                            Text(conflict.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Section {
                Button {
                    mergingPerson = true
                } label: {
                    Label("Merge a duplicate into this person", systemImage: "person.2.slash")
                }
            } footer: {
                Text("Pick another entry for the same person — their entries move here and the duplicate is removed.")
            }
            Section("Entries") {
                if entries.isEmpty {
                    Text("No entries yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        NavigationLink {
                            DiaryPageView(experience: entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title).font(.subheadline)
                                Text(entry.timelineDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(person.fullDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPeopleMap = true
                } label: {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                }
                .accessibilityLabel("People map")
            }
        }
        .sheet(isPresented: $addingRelationship) {
            AddRelationshipSheet(person: person)
        }
        .sheet(isPresented: $mergingPerson) {
            MergePersonSheet(survivor: person)
        }
        .sheet(isPresented: $showingPeopleMap) {
            PeopleGraphSheet(focusName: person.fullDisplayName)
        }
    }

    /// Renders an edge from this person's perspective: "<Type> · <other name>".
    @ViewBuilder
    private func relationshipRow(_ edge: PersonRelationship) -> some View {
        let other = (edge.subject === person) ? edge.object : edge.subject
        let label = perspectiveLabel(edge)
        HStack {
            Text(label)
            Spacer()
            Text(other?.name ?? "—").foregroundStyle(.secondary)
        }
    }

    /// The relationship word from this person's side. Inverse pairs (parent↔child,
    /// grandparent↔grandchild, aunt/uncle↔niece/nephew, in-laws) flip when viewed
    /// from the object's side; symmetric types read the same both ways.
    private func perspectiveLabel(_ edge: PersonRelationship) -> String {
        (edge.subject === person) ? edge.type.label : edge.type.inverseLabel
    }
}

/// A focused graph browser that can be opened from a diary page or person page,
/// instead of requiring a detour through the People tab.
struct PeopleGraphSheet: View {
    let focusName: String?
    @State private var mode: PeopleViewMode = .graph3D
    @Environment(\.dismiss) private var dismiss

    init(focusName: String? = nil) {
        self.focusName = focusName
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Map", selection: $mode) {
                    Label("2D", systemImage: PeopleViewMode.graph2D.systemImage).tag(PeopleViewMode.graph2D)
                    Label("3D", systemImage: PeopleViewMode.graph3D.systemImage).tag(PeopleViewMode.graph3D)
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                if let focusName {
                    Label(focusName, systemImage: "scope")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                Group {
                    if mode == .graph2D {
                        PeopleGraphView()
                    } else {
                        PeopleGraph3DView()
                    }
                }
            }
            .navigationTitle("People Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// "<person> is <type> of <other>" — creates a directed relationship edge.
struct AddRelationshipSheet: View {
    let person: Person
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var type: RelationshipType = .spouse
    @State private var otherId: PersistentIdentifier?

    private var candidates: [Person] { allPeople.filter { $0 !== person } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Relationship", selection: $type) {
                        ForEach(RelationshipType.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Of", selection: $otherId) {
                        Text("Choose…").tag(PersistentIdentifier?.none)
                        ForEach(candidates) { p in
                            Text(p.isMe ? "Me" : p.displayName(among: allPeople)).tag(Optional(p.persistentModelID))
                        }
                    }
                } header: {
                    Text("\(person.name) is…")
                } footer: {
                    Text("e.g. \(person.name) is Spouse of Me, or Parent of Emma.")
                }
            }
            .navigationTitle("Add Relationship")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.disabled(otherId == nil)
                }
            }
        }
    }

    private func save() {
        guard let otherId, let other = allPeople.first(where: { $0.persistentModelID == otherId }) else { return }
        modelContext.insert(PersonRelationship(subject: person, type: type, object: other))
        dismiss()
    }
}

/// Pick a duplicate to fold into `survivor`. The chosen person's entries and
/// relationships move onto the survivor and the duplicate is deleted.
struct MergePersonSheet: View {
    let survivor: Person
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var selectedId: PersistentIdentifier?
    @State private var confirming = false

    /// Everyone but the survivor. Same-name entries (the usual duplicate) float up.
    private var candidates: [Person] {
        allPeople
            .filter { $0 !== survivor }
            .sorted { a, b in
                let aMatch = a.name == survivor.name, bMatch = b.name == survivor.name
                if aMatch != bMatch { return aMatch }
                return a.name < b.name
            }
    }

    private var selected: Person? {
        allPeople.first { $0.persistentModelID == selectedId }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(candidates) { p in
                        Button {
                            selectedId = p.persistentModelID
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.fullDisplayName)
                                    Text("\(p.experiences.count) \(p.experiences.count == 1 ? "entry" : "entries")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if p.persistentModelID == selectedId {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Merge into \(survivor.fullDisplayName)")
                } footer: {
                    Text("The person you pick is removed; their entries and relationships move to \(survivor.fullDisplayName).")
                }
            }
            .navigationTitle("Merge Duplicate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") { confirming = true }.disabled(selectedId == nil)
                }
            }
            .confirmationDialog(
                "Merge \(selected?.fullDisplayName ?? "this person") into \(survivor.fullDisplayName)?",
                isPresented: $confirming,
                titleVisibility: .visible
            ) {
                Button("Merge", role: .destructive) { performMerge() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func performMerge() {
        guard let selected else { return }
        PersonMerger.merge(selected, into: survivor, in: modelContext)
        dismiss()
    }
}
