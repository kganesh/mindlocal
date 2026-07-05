import Foundation
import SwiftData

/// A calendar event the user plans to attend. The app proactively suggests
/// advice for it, grounded in the user's relevant past decisions and
/// experiences. Advice is cached once generated.
@Model
final class Event {
    var id: UUID
    var createdAt: Date
    var title: String
    var notes: String
    var date: Date
    var domainRaw: String
    var generatedAdvice: String?
    var adviceGeneratedAt: Date?

    var domain: Domain {
        get { Domain(rawValue: domainRaw) ?? .other }
        set { domainRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        title: String,
        notes: String = "",
        date: Date = .now,
        domain: Domain = .other,
        generatedAdvice: String? = nil,
        adviceGeneratedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.notes = notes
        self.date = date
        self.domainRaw = domain.rawValue
        self.generatedAdvice = generatedAdvice
        self.adviceGeneratedAt = adviceGeneratedAt
    }
}
