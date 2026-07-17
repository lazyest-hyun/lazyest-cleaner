import Foundation

enum CleanupRisk: Int, CaseIterable, Codable, Comparable, Sendable {
    case safe
    case review
    case sensitive
    case protected

    static func < (lhs: CleanupRisk, rhs: CleanupRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .safe: "안전"
        case .review: "검토"
        case .sensitive: "민감"
        case .protected: "보호"
        }
    }

    var symbol: String {
        switch self {
        case .safe: "checkmark.shield"
        case .review: "exclamationmark.triangle"
        case .sensitive: "hand.raised"
        case .protected: "lock.fill"
        }
    }
}

enum CleanupRecommendation: String, Codable, Sendable {
    case recommended
    case optional
    case avoid

    var title: String {
        switch self {
        case .recommended: "추천"
        case .optional: "선택"
        case .avoid: "제외"
        }
    }
}
