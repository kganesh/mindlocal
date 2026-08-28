import Foundation

/// Turns the markdown the app renders on screen into something worth hearing.
///
/// Advise replies, journal summaries and coaching notes all come back as
/// markdown and are rendered with `MarkdownRendering`. Handed to a synthesiser
/// verbatim, the markup gets pronounced: asterisks, hashes and bare URLs read
/// aloud as themselves. Both engines have the problem — Apple's is just as
/// literal as Kokoro's.
///
/// Deliberately conservative. It only strips markers where markdown requires
/// them to be (list and heading markers at the start of a line, emphasis
/// wrapped tightly around text), so ordinary prose containing a hyphen, an
/// asterisk or an underscore survives untouched.
struct SpeechTextSanitizer {

    func plainText(from markdown: String) -> String {
        var lines: [String] = []

        for rawLine in markdown.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)

            // Rules and table borders carry no speech.
            if isDecoration(line) { continue }

            let wasListItem = isListItem(line)
            line = stripLinePrefixes(line)
            line = stripInline(line)
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // List items rarely end in punctuation, so without this the
            // sentence tokenizer runs the whole list together as one breathless
            // sentence and the chunker can't find anywhere to split.
            if wasListItem, let last = line.last, !".!?:;,".contains(last) {
                line += "."
            }
            lines.append(line)
        }

        return lines.joined(separator: " ")
    }

    // MARK: - Line level

    private func isDecoration(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard !stripped.isEmpty else { return false }
        // --- *** ___ and |---|---| table rules
        return stripped.allSatisfy { "-*_".contains($0) } && stripped.count >= 3
            || stripped.allSatisfy { "|-:".contains($0) } && stripped.contains("|")
    }

    private func isListItem(_ line: String) -> Bool {
        line.range(of: "^([-*+]|\\d+\\.)\\s+", options: .regularExpression) != nil
    }

    /// Heading, blockquote and list markers — only at the start of a line,
    /// which is the only place markdown gives them meaning.
    private func stripLinePrefixes(_ line: String) -> String {
        var result = line
        for pattern in ["^#{1,6}\\s+", "^>\\s*", "^([-*+]|\\d+\\.)\\s+"] {
            result = result.replacingOccurrences(of: pattern, with: "",
                                                 options: .regularExpression)
        }
        return result
    }

    // MARK: - Inline

    private func stripInline(_ line: String) -> String {
        var result = line

        // Images before links: the alt text is the only speakable part, and
        // `![alt](url)` would otherwise leave a stray "!".
        result = replace(result, "!\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1")
        result = replace(result, "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1")

        // Code before emphasis — backticks can legitimately contain asterisks.
        result = replace(result, "`([^`]+)`", with: "$1")

        // Emphasis, longest marker first so `**` isn't eaten as two `*`.
        // The inner group forbids leading/trailing spaces so "2 * 3 * 4" and
        // snake_case_names are left alone.
        for pattern in ["\\*\\*(\\S(?:[^*]*\\S)?)\\*\\*",
                        "__(\\S(?:[^_]*\\S)?)__",
                        "\\*(\\S(?:[^*]*\\S)?)\\*",
                        "(?<![A-Za-z0-9_])_(\\S(?:[^_]*\\S)?)_(?![A-Za-z0-9_])"] {
            result = replace(result, pattern, with: "$1")
        }

        // A bare URL read character by character is unbearable; say nothing.
        result = replace(result, "https?://\\S+", with: "")

        return replace(result, "\\s{2,}", with: " ")
    }

    private func replace(_ text: String, _ pattern: String, with template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
}
