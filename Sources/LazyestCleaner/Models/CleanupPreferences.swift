import Foundation

struct CleanupPreferences: Codable, Sendable {
    var autoScan: Bool = false
    var includeHiddenFiles: Bool = false
    var allowImmediateRemoval: Bool = false
    var includeDockerVolumes: Bool = false
    var includeSystemApplicationsInFullScan: Bool = false
    var includeDockerInFullScan: Bool = false
    var largeFileThreshold: Int64 = 500_000_000
    var oldFileDays: Int = 90
    var duplicateMinimumSize: Int64 = 10_000_000
    var customScanRoots: [URL] = []
    var customProtectedPaths: [URL] = []
}
