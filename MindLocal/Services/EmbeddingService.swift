import Foundation
import NaturalLanguage

/// On-device sentence embeddings (Apple NaturalLanguage) for semantic retrieval.
/// No network, no model download — fully private.
enum EmbeddingService {
    private static let model = NLEmbedding.sentenceEmbedding(for: .english)

    /// A fixed-dimension embedding for a short piece of text, or nil if
    /// embeddings aren't available or the text is empty.
    static func vector(for text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let model,
              let v = model.vector(for: trimmed.lowercased()) else { return nil }
        return v.map(Float.init)
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }
}

extension EmbeddingService {
    /// Representative text for an entry (what it's "about").
    static func experienceText(_ e: Experience) -> String {
        ([e.title, e.summary, e.feelings, e.learning] + e.tags + e.people)
            .filter { !$0.isEmpty }.joined(separator: ". ")
    }
    static func decisionText(_ d: Decision) -> String {
        [d.title, d.statement, d.rationale].filter { !$0.isEmpty }.joined(separator: ". ")
    }

    /// Computes and stores embeddings for an entry and its decisions on save.
    @MainActor
    static func embed(_ experience: Experience) {
        experience.embedding = vector(for: experienceText(experience)) ?? []
        for decision in experience.decisions {
            decision.embedding = vector(for: decisionText(decision)) ?? []
        }
    }
}

/// Ranks items by semantic similarity to a query, using each item's stored
/// embedding (computing it on the fly when missing). Falls back to the given
/// order (recency) when embeddings aren't available.
enum SemanticRetriever {
    static func topK<T>(
        _ items: [T],
        query: String,
        k: Int,
        text: (T) -> String,
        embedding: (T) -> [Float]
    ) -> [T] {
        guard let queryVector = EmbeddingService.vector(for: query) else {
            return Array(items.prefix(k))
        }
        let scored: [(item: T, score: Float)] = items.map { item in
            let stored = embedding(item)
            let vector = stored.isEmpty ? (EmbeddingService.vector(for: text(item)) ?? []) : stored
            return (item, EmbeddingService.cosine(queryVector, vector))
        }
        return scored
            .sorted { $0.score > $1.score }
            .prefix(k)
            .map(\.item)
    }
}
