import Foundation

enum CleanupItemKind: String, CaseIterable, Codable, Sendable {
    case application
    case appLeftover
    case file
    case folder
    case installer
    case duplicateOriginal
    case duplicateCopy
    case cache
    case browserCache
    case developerCache
    case dockerImage
    case dockerContainer
    case dockerVolume
    case dockerBuildCache
    case log
    case trash
    case custom

    var symbol: String {
        switch self {
        case .application: "macwindow"
        case .appLeftover: "shippingbox.and.arrow.backward"
        case .file: "doc"
        case .folder: "folder"
        case .installer: "shippingbox"
        case .duplicateOriginal: "1.square"
        case .duplicateCopy: "square.on.square"
        case .cache: "bolt.horizontal.circle"
        case .browserCache: "globe"
        case .developerCache: "hammer"
        case .dockerImage: "shippingbox"
        case .dockerContainer: "cube"
        case .dockerVolume: "externaldrive"
        case .dockerBuildCache: "wrench.and.screwdriver"
        case .log: "doc.text"
        case .trash: "trash"
        case .custom: "folder.badge.gearshape"
        }
    }
}

enum DockerPruneTarget: String, Codable, CaseIterable, Sendable {
    case images
    case containers
    case buildCache
    case volumes
    case system

    var title: String {
        switch self {
        case .images: "미사용 이미지"
        case .containers: "중지 컨테이너"
        case .buildCache: "빌드 캐시"
        case .volumes: "미사용 볼륨"
        case .system: "Docker 전체"
        }
    }
}

enum CleanupOperation: Codable, Equatable, Sendable {
    case recycle
    case removeImmediately
    case docker(DockerPruneTarget)
    case revealOnly
}

struct CleanupItem: Identifiable, Codable, Sendable {
    let id: String
    let category: CleanupCategory
    let kind: CleanupItemKind
    let name: String
    let url: URL?
    let size: Int64
    let modifiedAt: Date?
    let risk: CleanupRisk
    let recommendation: CleanupRecommendation
    let operation: CleanupOperation
    let source: String
    let detail: String?
    let protectedReason: String?
    let bundleIdentifier: String?
    let duplicateGroupID: String?
    let metadata: [String: String]

    var isProtected: Bool {
        risk == .protected || protectedReason != nil
    }

    var isSelectable: Bool {
        !isProtected && operation != .revealOnly
    }

    static func stableID(prefix: String, value: String) -> String {
        "\(prefix):\(value)"
    }
}
