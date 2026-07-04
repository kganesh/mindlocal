import SwiftUI
import SwiftData

/// Ask-AI tab: answers questions grounded in the user's saved decisions (spec §9).
struct AdviceView: View {
    @Query(sort: \Decision.createdAt, order: .reverse) private var decisions: [Decision]
    @State private var viewModel = AdviceViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Ask about a decision…", text: $viewModel.question, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(12)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))

                    Button {
                        let history = decisions.map(DecisionSummary.init)
                        Task { await viewModel.ask(history: history) }
                    } label: {
                        Label("Ask", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canAsk)

                    content

                    Spacer(minLength: 0)

                    Text("Grounded in your \(decisions.count) saved decision\(decisions.count == 1 ? "" : "s"). Runs on-device.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding()
            }
            .navigationTitle("Advise")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            if decisions.isEmpty {
                hint("Save a few decisions first — answers draw on your decision history.")
            } else {
                hint("Try: \"What did I decide about the job offer?\" or \"How do I usually handle money decisions?\"")
            }
        case .thinking:
            ProgressView("Thinking…")
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        case .answer(let text):
            VStack(alignment: .leading, spacing: 12) {
                Label("Answer", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
