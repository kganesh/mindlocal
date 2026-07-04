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
