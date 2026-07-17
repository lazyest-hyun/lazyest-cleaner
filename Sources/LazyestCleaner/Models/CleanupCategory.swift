import Foundation

enum SidebarGroup: String, CaseIterable, Identifiable, Sendable {
    case summary
    case files
    case data
    case tools
    case system

    var id: Self { self }

    var title: String {
        switch self {
        case .summary: "요약"
        case .files: "파일"
        case .data: "앱 데이터"
        case .tools: "도구"
        case .system: "시스템"
        }
    }
}

enum CleanupCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case overview
    case quickClean
    case applications
    case systemApplications
    case leftovers
    case largeFiles
    case oldFiles
    case duplicates
    case downloads
    case desktopMedia
    case caches
    case browserData
    case developerData
    case docker
    case logs
    case trash
    case custom
    case history
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "전체"
        case .quickClean: "빠른 정리"
        case .applications: "설치 앱"
        case .systemApplications: "시스템 앱"
        case .leftovers: "잔여 데이터"
        case .largeFiles: "대용량"
        case .oldFiles: "오래된 파일"
        case .duplicates: "중복"
        case .downloads: "다운로드"
        case .desktopMedia: "데스크톱 영상"
        case .caches: "캐시"
        case .browserData: "브라우저"
        case .developerData: "개발 도구"
        case .docker: "Docker"
        case .logs: "로그"
        case .trash: "휴지통"
        case .custom: "사용자 지정"
        case .history: "기록"
        case .settings: "설정"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .quickClean: "sparkles"
        case .applications: "app.dashed"
        case .systemApplications: "lock.square"
        case .leftovers: "shippingbox.and.arrow.backward"
        case .largeFiles: "externaldrive.badge.exclamationmark"
        case .oldFiles: "clock.arrow.circlepath"
        case .duplicates: "square.on.square"
        case .downloads: "arrow.down.circle"
        case .desktopMedia: "film"
        case .caches: "bolt.horizontal.circle"
        case .browserData: "globe"
        case .developerData: "hammer"
        case .docker: "shippingbox"
        case .logs: "doc.text.magnifyingglass"
        case .trash: "trash"
        case .custom: "folder.badge.plus"
        case .history: "clock"
        case .settings: "gearshape"
        }
    }

    var group: SidebarGroup {
        switch self {
        case .overview, .quickClean:
            .summary
        case .largeFiles, .oldFiles, .duplicates, .downloads, .desktopMedia, .custom:
            .files
        case .applications, .systemApplications, .leftovers, .caches, .browserData:
            .data
        case .developerData, .docker:
            .tools
        case .logs, .trash, .history, .settings:
            .system
        }
    }

    var supportsScan: Bool {
        self != .overview && self != .history && self != .settings
    }

    var requiresFullDiskAccess: Bool {
        switch self {
        case .leftovers, .largeFiles, .oldFiles, .duplicates, .downloads, .desktopMedia, .trash:
            true
        default:
            false
        }
    }

    static func categories(in group: SidebarGroup) -> [CleanupCategory] {
        allCases.filter { $0.group == group }
    }
}
