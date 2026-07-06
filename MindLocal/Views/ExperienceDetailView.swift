import SwiftUI
import SwiftData

struct ExperienceDetailView: View {
    @Bindable var experience: Experience

    var body: some View {
        Form {
            Section("Experience") {
                TextField("Title", text: $experience.title)
                TextField("What happened", text: $experience.summary, axis: .vertical)
                WordingEnhancer(text: $experience.summary)
            }
            Section("How it felt") {
                Picker("Tone", selection: $experience.toneRaw) {
                    ForEach(ExperienceTone.allCases) { tone in
                        Label(tone.label, systemImage: tone.symbol).tag(tone.rawValue)
                    }
                }
                TextField("Feelings", text: $experience.feelings, axis: .vertical)
                TextField("What made it that way", text: $experience.factors, axis: .vertical)
            }
            Section(experience.tone == .pleasant ? "To repeat" : "To handle better") {
                TextField("What you did", text: $experience.response, axis: .vertical)
                TextField("Takeaway", text: $experience.learning, axis: .vertical)
            }
            if !experience.decisions.isEmpty {
                Section("Decisions") {
                    ForEach(experience.decisions) { decision in
                        NavigationLink { DecisionDetailView(decision: decision) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(decision.title).font(.subheadline)
                                if !decision.statement.isEmpty {
                                    Text(decision.statement).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            Section("Classification") {
                DatePicker(
                    "When it happened",
                    selection: Binding(
                        get: { experience.occurredAt ?? experience.createdAt },
                        set: { experience.occurredAt = $0 }
                    )
                )
                Picker("Domain", selection: $experience.domainRaw) {
                    ForEach(Domain.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            if let raw = experience.rawText, !raw.isEmpty {
                Section("Original note") {
                    Text(raw).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(experience.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
