import Foundation
import SwiftData

/// One shared SwiftData container used by both the app UI and Siri App Intents,
/// so a Siri-logged entry lands in the same store the app shows.
enum SharedStore {
    static let schema = Schema([
        Decision.self, OptionConsidered.self, Outcome.self,
        Experience.self, Event.self, Person.self, PersonRelationship.self
    ])

    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        } catch {
            fatalError("Failed to create shared ModelContainer: \(error)")
        }
    }()
}
