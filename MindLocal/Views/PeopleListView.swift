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
                        Label(person.name, systemImage: person.isMe ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                        Spacer()
                        Text("\(person.experiences.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { modelContext.delete(people[i]) }
            }
        }
    }
}

/// A person's entries (filter-by-person) plus lightweight editing of their names.
struct PersonDetailView: View {
    @Bindable var person: Person
    @Environment(\.modelContext) private var modelContext
    @Query private var allRelationships: [PersonRelationship]
    @State private var addingRelationship = false

    private var entries: [Experience] {
        person.experiences.sorted { $0.timelineDate > $1.timelineDate }
    }

    /// Edges touching this person, rendered from this person's perspective.
    private var relationships: [PersonRelationship] {
        allRelationships.filter { $0.subject === person || $0.object === person }
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $person.name)
                Toggle("This is me", isOn: $person.isMe)
            }
            if !person.aliases.isEmpty {
                Section("Also called") {
                    Text(person.aliases.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
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
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingRelationship) {
            AddRelationshipSheet(person: person)
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
                            Text(p.isMe ? "Me" : p.name).tag(Optional(p.persistentModelID))
                        }
                    }
                } header: {
                    Text("\(person.name) is…")
                } footer: {
                    Text("e.g. \(person.name) is Spouse of Me, or Parent of Emma. Add yourself with the “This is me” toggle first if needed.")
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
