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
    /// Free-text location (city or address) used for weather-aware advice.
    var location: String = ""
    /// Whether it's an outdoor event — weather only factors in for outdoor ones.
    var isOutdoor: Bool = false
    var domainRaw: String
    var generatedAdvice: String?
    var adviceGeneratedAt: Date?
    /// EventKit identifier when imported from the iPhone Calendar (nil for
    /// events created in the app). Used to de-duplicate on re-import.
    var externalId: String?

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
        location: String = "",
        isOutdoor: Bool = false,
        domain: Domain = .other,
        generatedAdvice: String? = nil,
        adviceGeneratedAt: Date? = nil,
        externalId: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.notes = notes
        self.date = date
        self.location = location
        self.isOutdoor = isOutdoor
        self.domainRaw = domain.rawValue
        self.generatedAdvice = generatedAdvice
        self.adviceGeneratedAt = adviceGeneratedAt
        self.externalId = externalId
    }
}
