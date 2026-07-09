import SwiftUI
import SwiftData

/// Browse the people mentioned across entries — the filter-by-person surface.
struct PeopleListView: View {
    @Query(sort: \Person.name) private var people: [Person]

    var body: some View {
        NavigationStack {
            List {
                if people.isEmpty {
                    ContentUnavailableView(
                        "No People Yet",
                        systemImage: "person.2",
                        description: Text("People you mention in your entries show up here.")
                    )
                } else {
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
                }
            }
            .navigationTitle("People")
        }
    }
}

/// A person's entries (filter-by-person) plus lightweight editing of their names.
struct PersonDetailView: View {
    @Bindable var person: Person

    private var entries: [Experience] {
        person.experiences.sorted { $0.timelineDate > $1.timelineDate }
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
            Section("Entries") {
                if entries.isEmpty {
                    Text("No entries yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        NavigationLink {
                            ExperienceDetailView(experience: entry)
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
    }
}
