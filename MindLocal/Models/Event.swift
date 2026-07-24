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
    /// Place name (from the map picker or free text) used for weather-aware advice.
    var location: String = ""
    /// Coordinates from the map picker, when chosen — used for precise weather and
    /// the map preview. Nil for free-text-only or unset locations.
    var latitude: Double?
    var longitude: Double?
    /// Whether it's an outdoor event — weather only factors in for outdoor ones.
    var isOutdoor: Bool = false
    var domainRaw: String
    var generatedAdvice: String?
    var adviceGeneratedAt: Date?
    /// EventKit identifier when imported from the iPhone Calendar (nil for
    /// events created in the app). Used to de-duplicate on re-import.
    var externalId: String?
    /// Who this event is with, if set — drives the same-day reminder notification
    /// (any open `Reminder`s about this person get bundled into it).
    @Relationship var person: Person?
    /// On-device sentence embedding for semantic retrieval in Advise. Empty until
    /// computed at save time (mirrors `Experience.embedding`/`Decision.embedding`).
    var embedding: [Float] = []

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
        latitude: Double? = nil,
        longitude: Double? = nil,
        isOutdoor: Bool = false,
        domain: Domain = .other,
        generatedAdvice: String? = nil,
        adviceGeneratedAt: Date? = nil,
        externalId: String? = nil,
        person: Person? = nil,
        embedding: [Float] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.notes = notes
        self.date = date
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.isOutdoor = isOutdoor
        self.domainRaw = domain.rawValue
        self.person = person
        self.embedding = embedding
        self.generatedAdvice = generatedAdvice
        self.adviceGeneratedAt = adviceGeneratedAt
        self.externalId = externalId
    }
}
