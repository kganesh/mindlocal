import SwiftUI

/// "Enhance wording" control for a text field. Runs an on-device grounded polish
/// and shows the result as an accept/reject preview — nothing is overwritten
/// unless the user taps "Use it".
struct WordingEnhancer: View {
    @Binding var text: String
    var extraction: ExtractionServicing = ExtractionService()

    @State private var phase: Phase = .idle

    private enum Phase: Equatable {
        case idle, working, preview(String), error(String)
    }

    private var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        switch phase {
        case .idle:
            Button {
                enhance()
            } label: {
                Label("Enhance wording", systemImage: "wand.and.stars")
                    .font(.callout)
            }
            .disabled(isBlank)

        case .working:
            HStack(spacing: 8) {
                ProgressView()
                Text("Enhancing…").foregroundStyle(.secondary)
            }

        case .preview(let improved):
            VStack(alignment: .leading, spacing: 10) {
                Text(improved)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Button("Use it") { text = improved; phase = .idle }
                        .buttonStyle(.borderedProminent)
                    Button("Keep original") { phase = .idle }
                        .buttonStyle(.bordered)
                }
            }

        case .error(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Spacer()
                Button("Dismiss") { phase = .idle }.font(.caption)
            }
        }
    }

    private func enhance() {
        let original = text
        phase = .working
        Task {
            do {
                let improved = try await extraction.enhanceWording(original)
                phase = .preview(improved)
            } catch ExtractionError.modelUnavailable {
                phase = .error("Apple Intelligence isn't available right now.")
            } catch {
                phase = .error("Couldn't enhance the wording.")
            }
        }
    }
}
