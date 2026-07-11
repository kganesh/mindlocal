import SwiftUI
import SwiftData

/// Guided, one-question-at-a-time step to confirm who ambiguous mentions (roles
/// like "my manager", or same-name people) refer to — before saving the entry.
/// Answers land in `viewModel.peopleAssignments` for PersonResolver.
struct PeopleConfirmView: View {
    let mentions: [String]
    @Bindable var viewModel: CaptureViewModel
    let onComplete: () -> Void

    @Query(sort: \Person.name) private var people: [Person]
    @State private var index = 0
    @State private var namingNew = false
    @State private var newName = ""

    private var current: String { mentions[min(index, mentions.count - 1)] }
    private var candidates: [Person] { people.filter { !$0.isMe } }

    var body: some View {
        VStack(spacing: 20) {
            Text("Question \(index + 1) of \(mentions.count)")
                .font(.caption).foregroundStyle(.secondary)

            Spacer()

            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("You mentioned “\(current)” —\nwho is this?")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            if !candidates.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(candidates) { person in
                            Button {
                                assign(person.name)
                            } label: {
                                Text(person.name).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    newName = ""; namingNew = true
                } label: {
                    Label("New person", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Not a person / skip") { assign("") }
                    .font(.callout)
            }
        }
        .padding()
        .navigationTitle("Confirm people")
        .navigationBarTitleDisplayMode(.inline)
        .alert("New person", isPresented: $namingNew) {
            TextField("Name", text: $newName)
            Button("Add") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                assign(name)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter a name for “\(current)”.")
        }
    }

    /// Record the answer (empty = skip) and advance, or finish.
    private func assign(_ name: String) {
        viewModel.peopleAssignments[current] = name
        if index + 1 < mentions.count {
            index += 1
        } else {
            onComplete()
        }
    }
}
