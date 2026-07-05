import SwiftUI
import SwiftData

struct DecisionDetailView: View {
    @Bindable var decision: Decision
    @State private var showingOutcomeSheet = false

    var body: some View {
        Form {
            Section("Decision") {
                TextField("Title", text: $decision.title)
                TextField("Statement", text: $decision.statement, axis: .vertical)
            }
            Section("Context") {
                TextField("Context", text: $decision.context, axis: .vertical)
            }
            if !decision.options.isEmpty {
                Section("Options Considered") {
                    ForEach(decision.options) { option in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.text)
                            if let why = option.rejectedBecause, !why.isEmpty {
                                Text("Rejected: \(why)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Rationale") {
                TextField("Rationale", text: $decision.rationale, axis: .vertical)
            }
            Section("Classification") {
                DatePicker(
                    "When you decided",
                    selection: Binding(
                        get: { decision.occurredAt ?? decision.createdAt },
                        set: { decision.occurredAt = $0 }
                    )
                )
                Picker("Domain", selection: $decision.domainRaw) {
                    ForEach(Domain.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Stakes", selection: $decision.stakesRaw) {
                    ForEach(Stakes.allCases) { Text($0.label).tag($0.rawValue) }
                }
                DatePicker(
                    "Revisit on",
                    selection: Binding(
                        get: { decision.revisitAt ?? .now.addingTimeInterval(90 * 86400) },
                        set: { decision.revisitAt = $0 }
                    ),
                    displayedComponents: .date
                )
            }
            Section("Outcome") {
                if let outcome = decision.outcome {
                    LabeledContent("Result", value: outcome.result.label)
                    if !outcome.notes.isEmpty {
                        Text(outcome.notes)
                    }
                    LabeledContent("Recorded", value: outcome.recordedAt.formatted(date: .abbreviated, time: .omitted))
                } else {
                    Button("Record Outcome") { showingOutcomeSheet = true }
                }
            }
            if let transcript = decision.rawTranscript, !transcript.isEmpty {
                Section("Original Note") {
                    Text(transcript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // M2: related-decisions section via embedding similarity (spec §4).
        }
        .navigationTitle(decision.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingOutcomeSheet) {
            OutcomeEntryView(decision: decision)
        }
    }
}

/// One-tap outcome entry (spec §4 — outcome loop).
struct OutcomeEntryView: View {
    @Bindable var decision: Decision
    @Environment(\.dismiss) private var dismiss
    @State private var result: OutcomeResult = .workedOut
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("How did it go?", selection: $result) {
                    ForEach(OutcomeResult.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                TextField("Notes (optional)", text: $notes, axis: .vertical)
            }
            .navigationTitle("Record Outcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        decision.outcome = Outcome(result: result, notes: notes)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
