import Foundation
import FoundationModels

/// Guided-generation target for an interpersonal conflict extracted from an entry.
/// Grounded in the note — an empty `about` means "not a real conflict" and is
/// dropped, mirroring `DecisionDraft`'s empty-`statement` rule.
@Generable
struct ConflictDraft: Equatable {
    @Guide(description: "Who the disagreement, argument, or tension was with — a specific person by name or relationship (e.g. 'Akhil', 'my manager', 'Mom').")
    var with: String

    @Guide(description: "What the disagreement was about, in a short phrase or sentence, in the writer's own words.")
    var about: String

    @Guide(description: "How the writer felt about it.")
    var feelings: String

    @Guide(description: "How it stood by the end of the note. One of: resolved, unresolved, ongoing. Default unresolved.")
    var resolution: String
}

extension ConflictDraft {
    var isConflict: Bool {
        !about.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toConflict() -> Conflict {
        Conflict(
            summary: about.trimmingCharacters(in: .whitespacesAndNewlines),
            personName: with.trimmingCharacters(in: .whitespacesAndNewlines),
            feelings: feelings.trimmingCharacters(in: .whitespacesAndNewlines),
            resolution: ConflictResolution(rawValue: resolution.lowercased()) ?? .unresolved
        )
    }
}
