import Foundation

/// Restricts the record lists that go to the advisor alongside the graph
/// context to a requested time window.
///
/// The graph retriever enforces its own window, but that only governs the
/// MEMORY GRAPH CONTEXT block. Decisions, experiences, reminders and events are
/// chosen separately, by semantic similarity, and similarity has no notion of
/// when something happened — asking "what did I do last week" pulled a decision
/// from a month earlier into PAST DECISIONS, and the model answered from it.
///
/// `QueryIntentDraft.hasStructure` cannot help: it covers tone, domain, topic
/// and count, with no time dimension at all, so a purely temporal question is
/// "unstructured" as far as that path is concerned.
enum TimeWindowFilter {

    /// Items whose date falls inside `window`. No window means no filtering.
    static func within<T>(_ items: [T], window: DateInterval?, date: (T) -> Date) -> [T] {
        guard let window else { return items }
        return items.filter { window.contains(date($0)) }
    }

    /// Note there is deliberately no "fall back to everything when the window
    /// is empty" variant. A week you wrote nothing in should produce no
    /// evidence — the advisor is already told to say when history doesn't
    /// cover something. Falling back would put a month-old decision in front
    /// of the model for a question about last week, which is the exact failure
    /// this exists to prevent.
}
