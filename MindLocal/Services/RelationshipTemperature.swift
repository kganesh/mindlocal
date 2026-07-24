import SwiftUI
import SwiftData
import UIKit

/// The emotional "temperature" of a relationship, computed from the conflicts the
/// journaler has recorded with a person plus how recently they've come up. Drives
/// edge and node color on the people graph. One axis: green (warm/healthy) → red
/// (in conflict), with a cool "dormant" state off the scale for ties gone quiet.
///
/// Hues are the design system's validated status palette (fixed across light/dark,
/// distinct from the categorical series). Each pairs with an SF Symbol so meaning
/// is never carried by color alone (the green↔red colorblind case).
enum RelationshipTemperature: String, CaseIterable, Identifiable {
    case inConflict, strained, cooling, warm, dormant
    var id: String { rawValue }

    /// An unresolved conflict newer than this still reads as actively hot.
    private static let recentWindow: TimeInterval = 30 * 86_400
    /// No mention for this long (and no conflict) → the tie is dormant.
    private static let dormantAfter: TimeInterval = 120 * 86_400

    var label: String {
        switch self {
        case .warm:       "Warm"
        case .cooling:    "Cooling"
        case .strained:   "Strained"
        case .inConflict: "In conflict"
        case .dormant:    "Dormant"
        }
    }

    /// Non-color cue paired with the hue in the legend, on nodes, and anywhere the
    /// temperature is shown — so it never rides on color alone.
    var symbol: String {
        switch self {
        case .warm:       "checkmark.circle.fill"
        case .cooling:    "exclamationmark.circle.fill"
        case .strained:   "exclamationmark.triangle.fill"
        case .inConflict: "flame.fill"
        case .dormant:    "moon.zzz.fill"
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    /// Validated status-palette hues (good/warning/serious/critical); dormant is a
    /// neutral slate that reads "off the scale".
    var uiColor: UIColor {
        switch self {
        case .warm:       UIColor(red: 0.047, green: 0.639, blue: 0.047, alpha: 1) // #0ca30c
        case .cooling:    UIColor(red: 0.980, green: 0.698, blue: 0.098, alpha: 1) // #fab219
        case .strained:   UIColor(red: 0.925, green: 0.514, blue: 0.353, alpha: 1) // #ec835a
        case .inConflict: UIColor(red: 0.816, green: 0.231, blue: 0.231, alpha: 1) // #d03b3b
        case .dormant:    UIColor(red: 0.471, green: 0.529, blue: 0.620, alpha: 1) // slate
        }
    }

    /// Hotter = higher; used to pick the dominant end of an edge and to order the legend.
    var severity: Int {
        switch self {
        case .inConflict: 4
        case .strained:   3
        case .cooling:    2
        case .warm:       1
        case .dormant:    0
        }
    }

    // MARK: - Computation

    /// A person's temperature from the conflicts recorded with them. "Me" is always
    /// warm (the anchor has no self-conflict). Reads model properties synchronously;
    /// callers are on the main actor.
    static func of(_ person: Person, conflicts allConflicts: [Conflict], now: Date = .now) -> RelationshipTemperature {
        if person.isMe { return .warm }
        let mine = allConflicts.filter { $0.withPerson === person }
        if mine.isEmpty {
            let lastSeen = person.experiences.map(\.timelineDate).max()
            if let lastSeen, now.timeIntervalSince(lastSeen) > dormantAfter { return .dormant }
            return .warm
        }
        if mine.contains(where: { $0.resolution == .ongoing }) { return .inConflict }
        let unresolved = mine.filter { $0.resolution == .unresolved }
        if let mostRecent = unresolved.map(\.createdAt).max() {
            return now.timeIntervalSince(mostRecent) <= recentWindow ? .inConflict : .strained
        }
        return .cooling   // only resolved conflicts remain
    }

    /// An edge takes the hotter of its two non-"Me" endpoints. The graph is
    /// Me-centric, so a Me↔X edge shows X's temperature directly.
    static func ofEdge(_ edge: PersonRelationship, conflicts allConflicts: [Conflict], now: Date = .now) -> RelationshipTemperature {
        let endpoints = [edge.subject, edge.object].compactMap { $0 }.filter { !$0.isMe }
        let temps = endpoints.map { of($0, conflicts: allConflicts, now: now) }
        return temps.max(by: { $0.severity < $1.severity }) ?? .warm
    }
}

/// Compact key for the temperatures actually present on a graph, hottest first.
struct TemperatureLegend: View {
    let present: [RelationshipTemperature]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(present) { t in
                HStack(spacing: 4) {
                    Image(systemName: t.symbol).foregroundStyle(t.color)
                    Text(t.label).foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption2)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
