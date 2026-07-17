import Foundation

actor StorageSnapshotService {
    func snapshot(for url: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> StorageSnapshot {
        let values = try url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return StorageSnapshot(total: total, available: available)
    }
}
