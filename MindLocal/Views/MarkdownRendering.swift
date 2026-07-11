import Foundation

extension String {
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
