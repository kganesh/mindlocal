import Foundation
import NaturalLanguage

extension String {
    /// Rewrites ISO dates as the app writes them elsewhere: "2026-07-10"
    /// becomes "Friday 10 July 2026".
    ///
    /// The context handed to the model uses `yyyy-MM-dd` and should keep doing
    /// so. It is what the grounding validator matches a cited date against, and
    /// it is unambiguous in a way no readable format is. So the conversion
    /// happens on the way out, for the two places a person meets the answer:
    /// the screen and the voice. Read aloud, an unconverted one comes out as
    /// "two thousand twenty-six dash zero seven".
    var withReadableDates: String {
        let pattern = #"\b(\d{4})-(\d{2})-(\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }

        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        let display = DateFormatter()
        display.dateFormat = "EEEE d MMMM yyyy"

        var result = self
        let matches = regex.matches(in: self, range: NSRange(startIndex..., in: self))
        // Right to left, so earlier ranges stay valid as the string changes.
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result),
                  let date = parser.date(from: String(result[range])) else { continue }
            result.replaceSubrange(range, with: display.string(from: date))
        }
        return result
    }

    /// Split into sentences, for rendering an answer as one bullet per
    /// sentence. The answer itself is never rewritten: read-aloud speaks the
    /// model's own string, bullets and all, which is why they live here rather
    /// than in the text.
    var sentences: [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = self
        var result: [String] = []
        tokenizer.enumerateTokens(in: startIndex..<endIndex) { range, _ in
            let sentence = self[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(sentence) }
            return true
        }
        // NLTokenizer returns nothing for input it can't tokenise, such as
        // punctuation alone. Showing it verbatim beats dropping it silently.
        return result.isEmpty ? [self] : result
    }

    /// Renders inline markdown (bold/italic) while preserving the line breaks
    /// and bullet layout the model produces.
    var renderedMarkdown: AttributedString {
        (try? AttributedString(
            markdown: self,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(self)
    }

    /// Plain text with markdown markers removed — for read-aloud so TTS doesn't
    /// speak the asterisks and dashes.
    var strippedMarkdown: String {
        replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: #"(?m)^\s*[-*]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^#+\s*"#, with: "", options: .regularExpression)
    }
}
