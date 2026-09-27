import SwiftUI
import SwiftData

/// How the People tab is presented: flat list, 2D graph, or 3D graph.
enum PeopleViewMode: String, CaseIterable, Identifiable {
    case list, graph2D, graph3D
    var id: String { rawValue }
    /// "Map", not "Graph (3D)". Every other route to this view already calls it
    /// a people map — the toolbar buttons, the sheet title — and the dimension
    /// count told the reader how it was built rather than what it shows. The
    /// flat variant keeps a distinguishing name only because it would need one
    /// if it ever came back alongside this.
    var title: String {
        switch self {
        case .list: return "List"
        case .graph2D: return "Flat Map"
        case .graph3D: return "Map"
        }
    }
    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .graph2D: return "circle.grid.2x2"
        case .graph3D: return "point.3.connected.trianglepath.dotted"
        }
    }

    /// What the UI offers. `graph2D` is hidden for now — the map covers the
    /// same ground and the pair invited a comparison the flat view lost.
    ///
    /// The case stays so `PeopleGraphView` keeps compiling and this is a one-line
    /// reversal rather than a resurrection.
    static var selectable: [PeopleViewMode] { [.list, .graph3D] }
}

/// Browse the people mentioned across entries — the filter-by-person surface.
struct PeopleListView: View {
    @Query(sort: \Person.name) private var people: [Person]
    @Environment(\.modelContext) private var modelContext
    @State private var mode: PeopleViewMode = .list
    /// The person just created by the + button, presented in the editor.
    @State private var newPerson: Person?
    /// Held separately because `newPerson` is already nil by the time
    /// `onDismiss` runs, and the cleanup needs to know who to check.
    @State private var pendingPerson: Person?
    @State private var searchText = ""

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
            .albumScreen()
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("View", selection: $mode) {
                            ForEach(PeopleViewMode.selectable) { m in
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
                        // Created with an EMPTY name, so the editor shows its
                        // "First name" placeholder rather than the literal "New
                        // Person", which the user then had to select and delete
                        // before typing.
                        //
                        // The insert has to happen now, because the editor binds
                        // to a live model. Dismissing without typing a name
                        // therefore has to undo it — see the sheet's onDismiss.
                        // The graph is rebuilt on Done rather than here, since a
                        // nameless person contributes nothing to it.
                        let person = Person(name: "")
                        modelContext.insert(person)
                        newPerson = person
                        pendingPerson = person
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add person")
                }
            }
            .onAppear { _ = Person.fetchOrCreateMe(in: modelContext) }
            // Straight to the editor, not the detail view. PersonDetailView is
            // for reading shared moments, and a person created a second ago has
            // none — it showed "Entries that mention New Person will collect
            // here" and required another tap on "Edit" to do the one
            // thing the + button was asking for.
            .sheet(item: $newPerson, onDismiss: discardUnnamedPerson) { person in
                NavigationStack {
                    PersonProfileEditor(person: person)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { newPerson = nil }
                            }
                        }
                }
            }
        }
    }

    /// Removes a person created by + who was never given a name.
    ///
    /// Tapping + has to insert immediately, because the editor binds to a live
    /// model. Without this, opening the editor and closing it left a nameless
    /// row behind every time — and before the name was blanked, a row literally
    /// called "New Person", several of which accumulated in testing.
    ///
    /// Only a still-empty name is discarded. Anything typed is kept, including a
    /// person given only a last name or a nickname.
    private func discardUnnamedPerson() {
        guard let person = pendingPerson else { return }
        pendingPerson = nil
        let named = !person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !person.lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if named {
            MemoryGraphStore.rebuildAndPersist(in: modelContext)
        } else {
            modelContext.delete(person)
        }
    }

    private var visiblePeople: [Person] {
        people.filter { person in
            searchText.isEmpty || person.fullDisplayName.localizedCaseInsensitiveContains(searchText)
                || person.aliases.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var listView: some View {
        List {
            AlbumHeading(title: "your people", subtitle: "Shared moments, remembered details.")
                .padding(.vertical, 16)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if visiblePeople.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(visiblePeople) { person in
                NavigationLink {
                    PersonDetailView(person: person)
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        AlbumMonogram(name: person.isMe ? "Me" : person.name)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(person.displayName(among: people))
                                .font(AlbumTheme.heading(.title3))
                                .foregroundStyle(AlbumTheme.ink)
                            if person.isMe {
                                Text("You").font(.caption).foregroundStyle(AlbumTheme.secondary)
                            } else if !person.occupation.isEmpty {
                                Text(person.occupation).font(.caption).foregroundStyle(AlbumTheme.secondary)
                            }
                            if let latest = person.experiences.max(by: { $0.timelineDate < $1.timelineDate }) {
                                Text("Last mentioned \(latest.timelineDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(AlbumTheme.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                }
                .listRowBackground(Color.clear)
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
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Find someone")
    }
}

/// Reading shared moments comes first; profile maintenance stays one tap away.
struct PersonDetailView: View {
    @Bindable var person: Person
    @State private var showingEditor = false
    @State private var showingMap = false
    @Query private var events: [Event]

    private var entries: [Experience] {
        person.experiences.sorted { $0.timelineDate > $1.timelineDate }
    }

    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 16) {
                AlbumMonogram(name: person.name)
                AlbumHeading(title: person.fullDisplayName,
                             subtitle: person.isMe ? "Your moments, collected." : nil)
                if !person.occupation.isEmpty {
                    Text(person.occupation).font(.subheadline).foregroundStyle(AlbumTheme.secondary)
                }
                if let latest = entries.first {
                    Text("Last mentioned \(latest.timelineDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(AlbumTheme.secondary)
                }
            }
            .padding(.vertical, 16)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if !person.reminders.isEmpty {
                Section("For next time") {
                    ForEach(person.reminders.sorted { $0.createdAt < $1.createdAt }) { reminder in
                        Button {
                            reminder.isDone ? reminder.markNotDone() : reminder.markDone()
                            Task { await EventReminderNotificationService.rescheduleAll(for: person, events: events) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: reminder.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(AlbumTheme.accent)
                                Text(reminder.text)
                                    .strikethrough(reminder.isDone)
                                    .foregroundStyle(AlbumTheme.ink)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(reminder.isDone ? "Mark as not done" : "Mark as done")
                        .listRowBackground(AlbumTheme.surface)
                    }
                }
            }

            if !person.likes.isEmpty || !person.dislikes.isEmpty {
                Section("Remembered details") {
                    if !person.likes.isEmpty {
                        LabeledContent("Likes", value: person.likes.joined(separator: ", "))
                    }
                    if !person.dislikes.isEmpty {
                        LabeledContent("Dislikes", value: person.dislikes.joined(separator: ", "))
                    }
                }
                .listRowBackground(AlbumTheme.surface)
            }

            Section("Shared moments") {
                if entries.isEmpty {
                    Text("Entries that mention \(person.name) will collect here.")
                        .font(.subheadline)
                        .foregroundStyle(AlbumTheme.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(entries) { entry in
                    NavigationLink { DiaryPageView(experience: entry) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.timelineDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(AlbumTheme.dateAccent)
                            ExperienceRow(experience: entry)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .albumScreen()
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEditor = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingMap = true } label: { Image(systemName: "point.3.connected.trianglepath.dotted") }
                    .accessibilityLabel("People map")
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                PersonProfileEditor(person: person)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingEditor = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingMap) { PeopleGraphSheet(focusName: person.fullDisplayName) }
    }
}

/// A person's entries (filter-by-person) plus lightweight editing of their names.
private struct PersonProfileEditor: View {
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
    @State private var confirmingDuplicateMerge = false
    @State private var newNickname = ""
    @State private var newLike = ""
    @State private var newDislike = ""

    /// Whether another person shares this person's first name — the moment a
    /// distinguisher (last name or context) becomes worth adding.
    private var sharesFirstName: Bool {
        allPeople.contains { $0 !== person && $0.name.caseInsensitiveCompare(person.name) == .orderedSame }
    }

    /// Another person with the same first *and* last name. This is what fixing a
    /// misspelling produces: a mis-heard "Akil" is extracted as a new person, and
    /// renaming it to "Akhil" leaves two identical nodes rather than one. Nothing
    /// merges them on its own — merging deletes a record, so it stays a decision
    /// the user makes — but at the moment the names line up it is offered here.
    ///
    /// Two different people can legitimately share a name, which is what the
    /// context qualifier is for, so two *different* non-empty qualifiers ("work"
    /// vs "cousin") mean the user has already said these are not the same person.
    private var exactDuplicate: Person? {
        let name = normalized(person.name)
        guard !name.isEmpty else { return nil }
        let last = normalized(person.lastName)
        let qualifier = normalized(person.qualifier)

        return allPeople.first { other in
            guard other !== person,
                  normalized(other.name) == name,
                  normalized(other.lastName) == last
            else { return false }
            let otherQualifier = normalized(other.qualifier)
            if qualifier.isEmpty || otherQualifier.isEmpty { return true }
            return qualifier == otherQualifier
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var entries: [Experience] {
        person.experiences.sorted { $0.timelineDate > $1.timelineDate }
    }

    private var trimmedNickname: String {
        newNickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only month/day matter for birthday-event derivation, so the year picked
    /// when first turning this on is arbitrary — the DatePicker still needs
    /// some starting value once toggled on, and clearing it back to nil on
    /// toggle-off is what stops the auto-derivation from running for them.
    private var birthdateToggleBinding: Binding<Bool> {
        Binding(
            get: { person.birthdate != nil },
            set: { isOn in person.birthdate = isOn ? (person.birthdate ?? .now) : nil }
        )
    }

    private var birthdateBinding: Binding<Date> {
        Binding(
            get: { person.birthdate ?? .now },
            set: { person.birthdate = $0 }
        )
    }

    /// Adds the typed nickname as an alias so future entries using it resolve to
    /// this person. Skips blanks and any spelling this person already answers to.
    private func addNickname() {
        let name = trimmedNickname
        guard !name.isEmpty, !person.matches(name) else { newNickname = ""; return }
        person.aliases.append(name)
        newNickname = ""
    }

    /// Inserted at the front, matching the same "most recent first" convention
    /// used when a like/dislike is extracted from an entry — a manually-added
    /// one is no less current than one mentioned in today's journal entry.
    private func addLike() {
        let item = newLike.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty, !person.likes.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) else {
            newLike = ""; return
        }
        person.likes.insert(item, at: 0)
        newLike = ""
    }

    private func addDislike() {
        let item = newDislike.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty, !person.dislikes.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) else {
            newDislike = ""; return
        }
        person.dislikes.insert(item, at: 0)
        newDislike = ""
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

    /// The merge offer, shown the moment the two names match. It names the entry
    /// count because that is what the user is really being asked about: which
    /// record holds the history, and what moves where.
    @ViewBuilder
    private func duplicateSection(_ duplicate: Person) -> some View {
        Section {
            Button {
                confirmingDuplicateMerge = true
            } label: {
                Label("Merge them into this one", systemImage: "arrow.triangle.merge")
            }
        } header: {
            Text("Possible duplicate")
        } footer: {
            Text("There is already a \(person.fullDisplayName) with \(entryCount(duplicate)). Merging moves those entries, relationships and details here, keeps \"\(duplicate.name)\" as a nickname so older mentions still resolve, and removes the other record.")
        }
    }

    private func entryCount(_ other: Person) -> String {
        let count = other.experiences.count
        return count == 1 ? "1 entry" : "\(count) entries"
    }

    private func mergeDuplicate() {
        guard let duplicate = exactDuplicate else { return }
        PersonMerger.merge(duplicate, into: person, in: modelContext)
        MemoryGraphStore.rebuildAndPersist(in: modelContext)
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
                // Still shown alongside the merge offer below. Two people with
                // the same bare first name are either one person written twice
                // or two people who need telling apart, and only the user knows
                // which — so both routes stay on screen.
                if sharesFirstName && person.distinguisher.isEmpty {
                    Label("Someone else is also named \(person.name). Add a last name or context to tell them apart.",
                          systemImage: "person.2.fill")
                }
            }
            if let duplicate = exactDuplicate {
                duplicateSection(duplicate)
            }
            Section {
                TextField("Occupation (optional)", text: $person.occupation)
                Toggle("Birthday", isOn: birthdateToggleBinding)
                if person.birthdate != nil {
                    DatePicker("Birthdate", selection: birthdateBinding, displayedComponents: .date)
                }
            } header: {
                Text("Details")
            } footer: {
                if person.birthdate != nil {
                    Text("An upcoming birthday event is added automatically each year.")
                }
            }
            Section {
                ForEach(person.likes, id: \.self) { like in
                    Text(like)
                }
                .onDelete { person.likes.remove(atOffsets: $0) }
                HStack {
                    TextField("Add something they like", text: $newLike)
                        .autocorrectionDisabled()
                        .onSubmit(addLike)
                    Button("Add", action: addLike)
                        .disabled(newLike.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Likes")
            }
            Section {
                ForEach(person.dislikes, id: \.self) { dislike in
                    Text(dislike)
                }
                .onDelete { person.dislikes.remove(atOffsets: $0) }
                HStack {
                    TextField("Add something they dislike", text: $newDislike)
                        .autocorrectionDisabled()
                        .onSubmit(addDislike)
                    Button("Add", action: addDislike)
                        .disabled(newDislike.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Dislikes")
            } footer: {
                Text("Extracted automatically when an entry mentions a preference, most recent first. Edit or swipe to remove.")
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
        .albumScreen()
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
        .confirmationDialog(
            "Merge the other \(person.fullDisplayName) into this one?",
            isPresented: $confirmingDuplicateMerge,
            titleVisibility: .visible
        ) {
            Button("Merge", role: .destructive) { mergeDuplicate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
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
                if let focusName {
                    Label(focusName, systemImage: "scope")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                PeopleGraph3DView()
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
        MemoryGraphStore.rebuildAndPersist(in: modelContext)
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
        MemoryGraphStore.rebuildAndPersist(in: modelContext)
        dismiss()
    }
}
