import Foundation
import NaturalLanguage

/// Splits text into speakable chunks.
///
/// Read-aloud can hand a whole paragraph to the synthesiser and wait. A
/// conversation cannot: a neural engine that runs 3× faster than real time
/// still costs real wall-clock on a long reply, and in dialogue that leading
/// silence reads as the app being broken. Chunking lets playback of the first
/// sentence start while the second is still being synthesised.
///
/// Sentence boundaries come from `NLTokenizer` rather than a regex on `.` — it
/// gets "Dr. Smith" and "3.5 hours" right, and mid-sentence splits are audible
/// as a wrong-sounding pause.
struct SpeechChunker {

    /// Upper bound on a chunk, in characters.
    ///
    /// Caps worst-case latency before the first sound: the longer a chunk, the
    /// longer the wait. Roughly 15 seconds of speech.
    var maxCharacters = 240

    /// Chunks below this get merged into their neighbour.
    ///
    /// Each chunk carries fixed synthesis overhead, and a lone "Yes." costs
    /// nearly as much as a full sentence while adding an unnatural seam.
    var minCharacters = 40

    func chunks(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var chunks: [String] = []
        var current = ""

        for sentence in sentences(in: trimmed) {
            // A single sentence over the cap has to be broken internally —
            // preferably at a clause boundary, where a pause sounds intended.
            guard sentence.count <= maxCharacters else {
                if !current.isEmpty { chunks.append(current); current = "" }
                chunks.append(contentsOf: split(longSentence: sentence))
                continue
            }

            if current.isEmpty {
                current = sentence
            } else if current.count + 1 + sentence.count <= maxCharacters {
                current += " " + sentence
            } else {
                chunks.append(current)
                current = sentence
            }
        }
        if !current.isEmpty { chunks.append(current) }

        return merge(chunks)
    }

    // MARK: - Sentences

    private func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(sentence) }
            return true
        }
        // NLTokenizer returns nothing for input it can't tokenise (e.g. only
        // punctuation); speaking it verbatim beats dropping it silently.
        return result.isEmpty ? [text] : result
    }

    /// Breaks an over-long sentence at clause boundaries, then at whitespace.
    private func split(longSentence sentence: String) -> [String] {
        var pieces: [String] = []
        var current = ""

        for clause in clauses(in: sentence) {
            if current.isEmpty {
                current = clause
            } else if current.count + 1 + clause.count <= maxCharacters {
                current += " " + clause
            } else {
                pieces.append(current)
                current = clause
            }
        }
        if !current.isEmpty { pieces.append(current) }

        // Still too long means one clause exceeds the cap on its own — a run-on
        // with no punctuation. Fall back to word boundaries; never mid-word.
        return pieces.flatMap { $0.count <= maxCharacters ? [$0] : splitOnWords($0) }
    }

    /// Splits on clause punctuation, keeping the punctuation attached so the
    /// synthesiser still hears the comma and inflects for it.
    private func clauses(in sentence: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in sentence {
            current.append(character)
            if ",;:—".contains(character) {
                let piece = current.trimmingCharacters(in: .whitespaces)
                if !piece.isEmpty { result.append(piece) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { result.append(tail) }
        return result.isEmpty ? [sentence] : result
    }

    private func splitOnWords(_ text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= maxCharacters {
                current += " " + word
            } else {
                pieces.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    // MARK: - Merging

    /// Folds a runt trailing chunk back into its predecessor.
    ///
    /// Only the tail needs this — the main loop already packs greedily, so an
    /// undersized chunk can only appear where a boundary forced one.
    private func merge(_ chunks: [String]) -> [String] {
        guard chunks.count > 1 else { return chunks }
        var result = chunks
        if let last = result.last, last.count < minCharacters,
           let previous = result.dropLast().last,
           previous.count + 1 + last.count <= maxCharacters {
            result.removeLast()
            result[result.count - 1] = previous + " " + last
        }
        return result
    }
}
