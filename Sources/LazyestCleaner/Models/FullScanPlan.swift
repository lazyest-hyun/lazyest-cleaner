import Foundation

struct FullScanPlan: Sendable {
    let includeSystemApplications: Bool
    let includeDocker: Bool
    let includeCustomLocations: Bool

    var categories: [CleanupCategory] {
        var result: [CleanupCategory] = [
            .caches,
            .browserData,
            .developerData,
            .logs,
            .applications,
            .leftovers,
            .largeFiles,
            .oldFiles,
            .duplicates,
            .downloads,
            .desktopMedia,
            .trash,
        ]
        if includeSystemApplications {
            result.insert(.systemApplications, after: .applications)
        }
        if includeDocker {
            result.insert(.docker, after: .developerData)
        }
        if includeCustomLocations {
            result.append(.custom)
        }
        return result
    }
}

private extension Array where Element: Equatable {
    mutating func insert(_ element: Element, after anchor: Element) {
        guard let index = firstIndex(of: anchor) else {
            append(element)
            return
        }
        insert(element, at: index + 1)
    }
}
