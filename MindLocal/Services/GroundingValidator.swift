import Foundation

/// Checks a `GroundedAnswer` against the context the model was actually given.
///
/// What this catches: references to things that were never supplied — an
/// Evidence number that doesn't exist, a person named nowhere in the context, a
/// date no node carries. That is the failure mode already observed in this app
/// (see `AdviceService.answerWhoIs`, where the model "fabricated a relationship
/// and even cited an entry that never mentioned the name at all").
///
/// What this does NOT catch: an answer that cites real evidence but misdescribes
/// it. "Evidence 2 says the meeting went badly" passes every check here if
/// Evidence 2 exists, whatever it actually says. Verifying that needs entailment
/// checking, which is a different and much harder problem. Treat `isGrounded` as
/// "invented no sources," not "is true."
enum GroundingValidator {

    static func validate(_ answer: GroundedAnswer,
                         against context: MemoryGraphContextPacker.PackedContext) -> GroundingReport {
        var report = GroundingReport()

        // Evidence is cited by its 1-based line number, so anything outside
        // 1...count refers to a line the model was never shown.
        let validRange = 1...max(context.evidenceTitles.count, 0)
        report.unknownEvidence = answer.citedEvidence
            .filter { context.evidenceTitles.isEmpty || !validRange.contains($0) }
            .sorted()

        // Names are compared case- and whitespace-insensitively, and a cited
        // name counts as known if it is a component of a fuller name in the
        // context: the answer may reasonably say "Lilly" where the context
        // says "Lilly Kolekar".
        let knownPeople = context.knownPeople.map(normalize)
        report.unknownPeople = answer.citedPeople
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { cited in
                let needle = normalize(cited)
                return !knownPeople.contains { known in
                    known == needle
                        || known.split(separator: " ").contains(Substring(needle))
                }
            }

        // Dates must match exactly — the context prints them in one format and
        // the guide tells the model to copy them verbatim, so a near-miss here
        // means the model reformatted or invented one, both worth surfacing.
        report.unknownDates = answer.citedDates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !context.knownDates.contains($0) }

        // An answer that names people or states dates while citing no evidence
        // isn't necessarily wrong, but nothing about it can be verified — and
        // it is exactly the shape a confabulated answer takes.
        let makesSpecificClaims = !answer.citedPeople.isEmpty || !answer.citedDates.isEmpty
        report.citesNothing = answer.citedEvidence.isEmpty
            && makesSpecificClaims
            && !answer.usedGeneralKnowledge
            && !context.evidenceTitles.isEmpty

        return report
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
