import Foundation

/// Crash-safe transcript persistence (M1 acceptance: kill app mid-capture →
/// draft restored on relaunch). Writes the raw transcript to disk on every
/// update; cleared on save or explicit discard.
struct DraftStore {
    private static var url: URL {
        URL.documentsDirectory.appending(path: "pending-draft.json")
    }

    struct PendingDraft: Codable {
        var transcript: String
        var updatedAt: Date
    }

    static func save(transcript: String) {
        let draft = PendingDraft(transcript: transcript, updatedAt: .now)
        if let data = try? JSONEncoder().encode(draft) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load() -> PendingDraft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PendingDraft.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
