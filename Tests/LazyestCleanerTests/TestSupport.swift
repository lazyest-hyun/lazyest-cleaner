import Foundation
@testable import LazyestCleaner

enum TestSupport {
    static func makeFixtureDirectory() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: ".build/test-fixtures")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func makeItem(
        url: URL?,
        category: CleanupCategory = .largeFiles,
        kind: CleanupItemKind = .file,
        risk: CleanupRisk = .review,
        recommendation: CleanupRecommendation = .optional,
        operation: CleanupOperation = .recycle,
        protectedReason: String? = nil,
        name: String? = nil,
        bundleIdentifier: String? = nil
    ) -> CleanupItem {
        CleanupItem(
            id: "test:\(url?.path ?? UUID().uuidString)",
            category: category,
            kind: kind,
            name: name ?? url?.lastPathComponent ?? "Docker",
            url: url,
            size: 1_024,
            modifiedAt: Date(),
            risk: protectedReason == nil ? risk : .protected,
            recommendation: recommendation,
            operation: operation,
            source: "테스트",
            detail: nil,
            protectedReason: protectedReason,
            bundleIdentifier: bundleIdentifier,
            duplicateGroupID: nil,
            metadata: [:]
        )
    }
}
