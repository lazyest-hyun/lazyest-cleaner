import Foundation

struct FileInventoryRecord: Sendable {
    let url: URL
    let size: Int64
    let modifiedAt: Date?
}

actor FileInventoryService {
    private struct CacheKey: Hashable {
        let roots: [String]
        let includesHiddenFiles: Bool
        let protectionRuleIDs: [String]
    }

    private struct CacheEntry {
        let createdAt: Date
        let records: [FileInventoryRecord]
    }

    private let fileManager: FileManager
    private let directoryAccess: any DirectoryAccessChecking
    private let maximumRecords = 100_000
    private let cacheLifetime: TimeInterval = 5 * 60
    private let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .fileSizeKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey,
        .contentModificationDateKey,
    ]

    private var cache: [CacheKey: CacheEntry] = [:]

    init(
        fileManager: FileManager = .default,
        directoryAccess: (any DirectoryAccessChecking)? = nil
    ) {
        self.fileManager = fileManager
        self.directoryAccess = directoryAccess ?? DirectoryAccessService()
    }

    func records(
        roots: [URL],
        includeHiddenFiles: Bool,
        policy: ProtectionPolicy
    ) async throws -> [FileInventoryRecord] {
        let key = CacheKey(
            roots: roots.map {
                $0.standardizedFileURL.resolvingSymlinksInPath().path
            }.sorted(),
            includesHiddenFiles: includeHiddenFiles,
            protectionRuleIDs: policy.rules.map(\.id).sorted()
        )
        if let cached = cache[key],
            Date().timeIntervalSince(cached.createdAt) < cacheLifetime
        {
            return cached.records
        }

        let fileManager = self.fileManager
        let existingRoots = roots.filter { fileManager.fileExists(atPath: $0.path) }
        guard !existingRoots.isEmpty else {
            cache[key] = CacheEntry(createdAt: Date(), records: [])
            return []
        }

        let directoryAccess = self.directoryAccess
        let probedRoots = await withTaskGroup(of: (Int, URL, Bool).self) { group in
            for (index, root) in existingRoots.enumerated() {
                group.addTask {
                    (index, root, await directoryAccess.canEnumerate(root))
                }
            }

            var values: [(Int, URL, Bool)] = []
            for await value in group {
                values.append(value)
            }
            return values.sorted { $0.0 < $1.0 }
        }
        let accessibleRoots = probedRoots.compactMap { _, root, canEnumerate in
            canEnumerate ? root : nil
        }
        guard !accessibleRoots.isEmpty else {
            throw DirectoryAccessError.permissionDenied("표준 폴더")
        }

        let options: FileManager.DirectoryEnumerationOptions =
            includeHiddenFiles
            ? []
            : [.skipsHiddenFiles]
        let maximumRecords = self.maximumRecords
        let perRootLimit = max(10_000, maximumRecords / accessibleRoots.count)
        let resourceKeys = self.resourceKeys
        let rootRecords = try await withThrowingTaskGroup(
            of: (Int, [FileInventoryRecord]).self
        ) { group in
            for (index, root) in accessibleRoots.enumerated() {
                group.addTask {
                    let records = try Self.enumerate(
                        root: root,
                        resourceKeys: resourceKeys,
                        options: options,
                        policy: policy,
                        limit: perRootLimit
                    )
                    return (index, records)
                }
            }

            var values: [(Int, [FileInventoryRecord])] = []
            for try await value in group {
                values.append(value)
            }
            return values.sorted { $0.0 < $1.0 }
        }
        let records = Array(
            rootRecords
                .flatMap { $0.1 }
                .prefix(maximumRecords)
        )

        cache[key] = CacheEntry(createdAt: Date(), records: records)
        return records
    }

    private nonisolated static func enumerate(
        root: URL,
        resourceKeys: Set<URLResourceKey>,
        options: FileManager.DirectoryEnumerationOptions,
        policy: ProtectionPolicy,
        limit: Int
    ) throws -> [FileInventoryRecord] {
        let fileManager = FileManager()
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(resourceKeys),
                options: options,
                errorHandler: { _, _ in true }
            )
        else {
            return []
        }

        var records: [FileInventoryRecord] = []
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            guard let values = try? url.resourceValues(forKeys: resourceKeys),
                values.isSymbolicLink != true
            else {
                enumerator.skipDescendants()
                continue
            }
            if values.isDirectory == true {
                if values.isPackage == true
                    || policy.shouldSkipDescendants(of: url)
                    || [".git", "node_modules"].contains(url.lastPathComponent)
                {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }
            records.append(
                FileInventoryRecord(
                    url: url,
                    size: Int64(
                        values.totalFileAllocatedSize
                            ?? values.fileAllocatedSize
                            ?? values.fileSize
                            ?? 0
                    ),
                    modifiedAt: values.contentModificationDate
                ))
            if records.count >= limit { break }
        }
        return records
    }

    func invalidate() {
        cache.removeAll()
    }
}
