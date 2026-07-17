import Foundation

enum ItemScopeFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case recommended
    case review
    case protected

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "전체"
        case .recommended: "추천"
        case .review: "검토"
        case .protected: "보호"
        }
    }
}

enum CleanupSortOrder: String, CaseIterable, Identifiable, Sendable {
    case sizeDescending
    case dateDescending
    case nameAscending
    case riskAscending

    var id: Self { self }

    var title: String {
        switch self {
        case .sizeDescending: "크기"
        case .dateDescending: "최근 수정"
        case .nameAscending: "이름"
        case .riskAscending: "위험도"
        }
    }
}

struct ActionResolution: Sendable {
    let descriptor: ActionDescriptor
    let isEnabled: Bool
    let disabledReason: String?
    let items: [CleanupItem]
}

struct CleanupConfirmationRequest: Identifiable, Sendable {
    let id = UUID()
    let action: CleanupActionID
    let items: [CleanupItem]

    var descriptor: ActionDescriptor {
        ActionCatalog.descriptor(for: action)
    }

    var bytes: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    var highestRisk: CleanupRisk {
        items.map(\.risk).max() ?? .safe
    }

    var needsAcknowledgement: Bool {
        descriptor.confirmation == .reinforced || highestRisk >= .sensitive
    }
}

enum CleanupNoticeKind: Sendable {
    case success
    case warning
    case error
}

struct CleanupNotice: Identifiable, Sendable {
    let id = UUID()
    let kind: CleanupNoticeKind
    let message: String
}

enum CleanupScanIssueKind: CaseIterable, Sendable {
    case permissionDenied
    case timedOut
    case unavailable
    case failed

    var symbol: String {
        switch self {
        case .permissionDenied: "lock.shield"
        case .timedOut: "clock.badge.exclamationmark"
        case .unavailable: "questionmark.app.dashed"
        case .failed: "xmark.octagon"
        }
    }
}

struct CleanupScanIssue: Sendable {
    let kind: CleanupScanIssueKind
    let title: String
    let detail: String
}
