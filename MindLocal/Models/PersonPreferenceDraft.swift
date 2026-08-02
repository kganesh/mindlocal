import Foundation
import FoundationModels

/// Guided-generation target for a specific named person's stated like or
/// dislike (e.g. "Akhil loves chocolate ice cream cake" -> Akhil / chocolate
/// ice cream cake / like). Grounded in the note; never invented. Deliberately
/// distinct from a one-off reaction to a single moment — see the extraction
/// instructions for the "stated preference vs. one-time reaction" distinction.
@Generable
struct PersonPreferenceDraft: Equatable {
    @Guide(description: "The person's name or relationship, exactly as mentioned (e.g. 'Akhil', 'my manager Sarah'). Empty if no specific person's preference is stated.")
    var name: String

    @Guide(description: "The specific thing they like or dislike, exactly as stated (e.g. 'chocolate ice cream cake', 'cilantro'). Empty if not stated.")
    var item: String

    @Guide(description: "Whether they like or dislike it, based on how they described it. One of: like, dislike.")
    var sentiment: String
}

extension PersonPreferenceDraft {
    var isPersonPreference: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && ["like", "dislike"].contains(sentiment.lowercased())
    }
}
