import Foundation
import SwiftData

/// A conviction / principle in the user's "you-model" — how they tend to think
/// and decide. In Phase 2 these are user-authored (a mirror they curate); Phase 3
/// will add AI-synthesized ones grounded in the decision→outcome aggregates.
@Model
final class Principle {
    var id: UUID
    var text: String
    var createdAt: Date
    /// True for principles the user wrote themselves (vs. AI-suggested later).
    var isUserAuthored: Bool

    init(id: UUID = UUID(), text: String, createdAt: Date = .now, isUserAuthored: Bool = true) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.isUserAuthored = isUserAuthored
    }
}
