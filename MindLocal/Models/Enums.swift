import Foundation

enum Domain: String, Codable, CaseIterable, Identifiable {
    case career, money, health, family, work, other
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum Stakes: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Whether an experience was positive, negative, or mixed — drives whether the
/// app helps the user recreate it (pleasant) or handle it better (unpleasant).
enum ExperienceTone: String, Codable, CaseIterable, Identifiable {
    case pleasant, unpleasant, mixed
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .pleasant: "sun.max.fill"
        case .unpleasant: "cloud.rain.fill"
        case .mixed: "cloud.sun.fill"
        }
    }
}

enum OutcomeResult: String, Codable, CaseIterable, Identifiable {
    case workedOut, mixed, regret, tooEarly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .workedOut: "Worked out"
        case .mixed: "Mixed"
        case .regret: "Regret"
        case .tooEarly: "Too early to tell"
        }
    }
}
