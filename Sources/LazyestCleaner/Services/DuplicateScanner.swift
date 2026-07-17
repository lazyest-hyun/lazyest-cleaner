import CryptoKit
import Foundation

actor DuplicateScanner {
    private let fileManager: FileManager
    private let home: URL
    private let fileInventory: FileInventoryService

    init(
        fileManager: FileManager = .default,
        home: URL? = nil,
        fileInventory: FileInventoryService? = nil
    ) {
        self.fileManager = fileManager
        self.home = home ?? fileManager.homeDirectoryForCurrentUser
        self.fileInventory = fileInventory ?? FileInventoryService()
    }

    func scan(
        preferences: CleanupPreferences,
        policy: ProtectionPolicy
    ) async throws -> [CleanupItem] {
        let roots =
            [
                home.appending(path: "Documents"),
                home.appending(path: "Downloads"),
                home.appending(path: "Desktop"),
            ] + preferences.customScanRoots
        let records = try await fileInventory.records(
            roots: roots,
            includeHiddenFiles: preferences.includeHiddenFiles,
            policy: policy
        )

        var bySize: [Int64: [FileInventoryRecord]] = [:]
        for record in records where record.size >= preferences.duplicateMinimumSize {
            bySize[record.size, default: []].append(record)
        }

        var byDigest: [String: [FileInventoryRecord]] = [:]
        for records in bySize.values where records.count > 1 {
            for record in records where fileManager.fileExists(atPath: record.url.path) {
                try Task.checkCancellation()
                let digest = try digest(of: record.url)
                byDigest[digest, default: []].append(record)
            }
        }

        var items: [CleanupItem] = []
        for (digest, matches) in byDigest where matches.count > 1 {
            let sorted = matches.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
            let groupID = String(digest.prefix(16))
            for (index, match) in sorted.enumerated() {
                let decision = policy.decision(for: match.url)
                let isOriginal = index == 0
                let protectedReason = isOriginal ? "기준 사본" : decision.reason
                items.append(
                    CleanupItem(
                        id: CleanupItem.stableID(
                            prefix: "duplicate:\(groupID)", value: match.url.standardizedFileURL.path),
                        category: .duplicates,
                        kind: isOriginal ? .duplicateOriginal : .duplicateCopy,
                        name: match.url.lastPathComponent,
                        url: match.url,
                        size: match.size,
                        modifiedAt: match.modifiedAt,
                        risk: protectedReason == nil ? .review : .protected,
                        recommendation: .avoid,
                        operation: isOriginal ? .revealOnly : .recycle,
                        source: "중복 \(groupID)",
                        detail: "\(matches.count)개 사본",
                        protectedReason: protectedReason,
                        bundleIdentifier: nil,
                        duplicateGroupID: groupID,
                        metadata: ["사본": "\(matches.count)"]
                    ))
            }
        }
        return items.sorted {
            if $0.duplicateGroupID == $1.duplicateGroupID {
                return $0.kind == .duplicateOriginal
            }
            return $0.size > $1.size
        }
    }

    private func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
            try Task.checkCancellation()
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
