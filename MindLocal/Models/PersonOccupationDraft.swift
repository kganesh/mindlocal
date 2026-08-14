import Foundation
import FoundationModels

/// Guided-generation target for a specific named person's occupation, if
/// explicitly stated in a diary entry (e.g. "David, a nurse, helped me move
/// the couch" -> David / nurse). Grounded in the note; never invented.
@Generable
struct PersonOccupationDraft: Equatable {
    @Guide(description: "The person's name or relationship, exactly as mentioned (e.g. 'David', 'my manager Sarah').")
    var name: String

    @Guide(description: "Their occupation or job title, exactly as stated (e.g. 'nurse', 'software engineer', 'retired').")
    var occupation: String
}

extension PersonOccupationDraft {
    var isPersonOccupation: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !occupation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
