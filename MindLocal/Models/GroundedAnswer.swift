import Foundation
import FoundationModels

/// Structured answer shape for the graph-backed advisor, replacing a bare
/// `String` so the answer can be checked against the context it was given.
///
/// The plain-prose answer was unverifiable: the model could name a person who
/// appears nowhere in the context, or state a date no entry carries, and
/// nothing downstream could tell. Each field below is something the packed
/// context also contains, so `GroundingValidator` can confirm the model is
/// referring to evidence that was actually supplied rather than invented.
///
/// Kept deliberately small. The guided-generation schema is sent to the model
/// along with the context, and this runs against a 4,096-token window — every
/// field here is one the validator genuinely uses.
@Generable
struct GroundedAnswer: Equatable {
    @Guide(description: "The answer itself, a few sentences.")
    var answer: String

    @Guide(description: "The numbers of the Evidence lines you actually used, e.g. [1, 3]. Empty if you used none of them.")
    var citedEvidence: [Int]

    @Guide(description: "Every person you named in the answer, spelled exactly as the context spells them.")
    var citedPeople: [String]

    @Guide(description: "Every date you stated in the answer, copied exactly as the context writes it (YYYY-MM-DD).")
    var citedDates: [String]

    @Guide(description: "True if any part of your answer is general guidance rather than something the context supports.")
    var usedGeneralKnowledge: Bool
}

/// What the validator found when checking a `GroundedAnswer` against the
/// context the model was actually given.
struct GroundingReport: Equatable {
    /// Cited evidence numbers with no matching line in the context — the model
    /// referred to a source that was never supplied.
    var unknownEvidence: [Int] = []
    /// Named people who appear nowhere in the context.
    var unknownPeople: [String] = []
    /// Stated dates carried by no node in the context.
    var unknownDates: [String] = []
    /// An answer that makes specific claims while citing nothing. Not proof of
    /// a hallucination on its own, but the answer is unverifiable either way.
    var citesNothing: Bool = false

    /// No fabricated reference of any kind. A grounded answer can still
    /// misdescribe a real entry — see `GroundingValidator`'s note on what this
    /// check does and does not cover.
    var isGrounded: Bool {
        unknownEvidence.isEmpty && unknownPeople.isEmpty && unknownDates.isEmpty
    }

    var hasFindings: Bool { !isGrounded || citesNothing }
}
