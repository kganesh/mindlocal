import Foundation
import SwiftData

/// One shared SwiftData container used by both the app UI and Siri App Intents,
/// so a Siri-logged entry lands in the same store the app shows.
enum SharedStore {
    static let schema = Schema([
        Decision.self, OptionConsidered.self, Outcome.self,
        Experience.self, Event.self, Person.self, PersonRelationship.self,
        Conflict.self, Reminder.self, Principle.self, MemoryGraphSnapshot.self
    ])

    /// True when running under XCTest — use a throwaway in-memory store so tests
    /// don't touch real data and there's a single container in the process.
    private static var underTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static let container: ModelContainer = {
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: underTest)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create shared ModelContainer: \(error)")
        }
    }()
}
