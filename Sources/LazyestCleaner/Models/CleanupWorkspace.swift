import Foundation

enum CleanupWorkspace: String, CaseIterable, Identifiable, Sendable {
    case overview
    case quick
    case applications
    case files
    case appData
    case developer
    case history
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "개요"
        case .quick: "빠른 정리"
        case .applications: "앱"
        case .files: "파일"
        case .appData: "앱 데이터"
        case .developer: "개발"
        case .history: "기록"
        case .settings: "설정"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.1x2"
        case .quick: "sparkles"
        case .applications: "app.dashed"
        case .files: "folder"
        case .appData: "externaldrive.badge.icloud"
        case .developer: "hammer"
        case .history: "clock"
        case .settings: "gearshape"
        }
    }

    var categories: [CleanupCategory] {
        switch self {
        case .overview: [.overview]
        case .quick: [.quickClean]
        case .applications: [.applications, .systemApplications, .leftovers]
        case .files: [.largeFiles, .oldFiles, .duplicates, .downloads, .desktopMedia, .custom]
        case .appData: [.caches, .browserData, .logs, .trash]
        case .developer: [.developerData, .docker]
        case .history: [.history]
        case .settings: [.settings]
        }
    }

    var defaultCategory: CleanupCategory {
        categories[0]
    }

    static func containing(_ category: CleanupCategory) -> CleanupWorkspace {
        allCases.first { $0.categories.contains(category) } ?? .overview
    }
}
