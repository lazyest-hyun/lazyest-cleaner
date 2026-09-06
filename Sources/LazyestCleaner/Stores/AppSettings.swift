import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let autoScan = "settings.autoScan"
        static let includeHiddenFiles = "settings.includeHiddenFiles"
        static let allowImmediateRemoval = "settings.allowImmediateRemoval"
        static let includeDockerVolumes = "settings.includeDockerVolumes"
        static let includeSystemApplicationsInFullScan = "settings.includeSystemApplicationsInFullScan"
        static let includeDockerInFullScan = "settings.includeDockerInFullScan"
        static let largeFileThreshold = "settings.largeFileThreshold"
        static let oldFileDays = "settings.oldFileDays"
        static let duplicateMinimumSize = "settings.duplicateMinimumSize"
        static let customScanRoots = "settings.customScanRoots"
        static let customProtectedPaths = "settings.customProtectedPaths"
    }

    private let defaults: UserDefaults

    var autoScan: Bool { didSet { defaults.set(autoScan, forKey: Key.autoScan) } }
    var includeHiddenFiles: Bool { didSet { defaults.set(includeHiddenFiles, forKey: Key.includeHiddenFiles) } }
    var allowImmediateRemoval: Bool {
        didSet { defaults.set(allowImmediateRemoval, forKey: Key.allowImmediateRemoval) }
    }
    var includeDockerVolumes: Bool { didSet { defaults.set(includeDockerVolumes, forKey: Key.includeDockerVolumes) } }
    var includeSystemApplicationsInFullScan: Bool {
        didSet { defaults.set(includeSystemApplicationsInFullScan, forKey: Key.includeSystemApplicationsInFullScan) }
    }
    var includeDockerInFullScan: Bool {
        didSet { defaults.set(includeDockerInFullScan, forKey: Key.includeDockerInFullScan) }
    }
    var largeFileThreshold: Int64 { didSet { defaults.set(largeFileThreshold, forKey: Key.largeFileThreshold) } }
    var oldFileDays: Int { didSet { defaults.set(oldFileDays, forKey: Key.oldFileDays) } }
    var duplicateMinimumSize: Int64 { didSet { defaults.set(duplicateMinimumSize, forKey: Key.duplicateMinimumSize) } }
    private(set) var customScanRoots: [URL]
    private(set) var customProtectedPaths: [URL]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults === UserDefaults.standard {
            LegacyMigration.migratePreferences(to: defaults)
        }
        autoScan = defaults.bool(forKey: Key.autoScan)
        includeHiddenFiles = defaults.bool(forKey: Key.includeHiddenFiles)
        allowImmediateRemoval = defaults.bool(forKey: Key.allowImmediateRemoval)
        includeDockerVolumes = defaults.bool(forKey: Key.includeDockerVolumes)
        includeSystemApplicationsInFullScan = defaults.bool(forKey: Key.includeSystemApplicationsInFullScan)
        includeDockerInFullScan = defaults.bool(forKey: Key.includeDockerInFullScan)
        let storedLargeThreshold = defaults.object(forKey: Key.largeFileThreshold) as? NSNumber
        largeFileThreshold = storedLargeThreshold?.int64Value ?? 500_000_000
        let storedOldDays = defaults.integer(forKey: Key.oldFileDays)
        oldFileDays = storedOldDays > 0 ? storedOldDays : 90
        let storedDuplicateThreshold = defaults.object(forKey: Key.duplicateMinimumSize) as? NSNumber
        duplicateMinimumSize = storedDuplicateThreshold?.int64Value ?? 10_000_000
        customScanRoots = Self.decodeURLs(defaults.data(forKey: Key.customScanRoots))
        customProtectedPaths = Self.decodeURLs(defaults.data(forKey: Key.customProtectedPaths))
    }

    var snapshot: CleanupPreferences {
        CleanupPreferences(
            autoScan: autoScan,
            includeHiddenFiles: includeHiddenFiles,
            allowImmediateRemoval: allowImmediateRemoval,
            includeDockerVolumes: includeDockerVolumes,
            includeSystemApplicationsInFullScan: includeSystemApplicationsInFullScan,
            includeDockerInFullScan: includeDockerInFullScan,
            largeFileThreshold: largeFileThreshold,
            oldFileDays: oldFileDays,
            duplicateMinimumSize: duplicateMinimumSize,
            customScanRoots: customScanRoots,
            customProtectedPaths: customProtectedPaths
        )
    }

    func addScanRoot(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !customScanRoots.contains(standardized) else { return }
        customScanRoots.append(standardized)
        customScanRoots.sort { $0.path < $1.path }
        save(customScanRoots, key: Key.customScanRoots)
    }

    func removeScanRoot(_ url: URL) {
        customScanRoots.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        save(customScanRoots, key: Key.customScanRoots)
    }

    func addProtectedPath(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !customProtectedPaths.contains(standardized) else { return }
        customProtectedPaths.append(standardized)
        customProtectedPaths.sort { $0.path < $1.path }
        save(customProtectedPaths, key: Key.customProtectedPaths)
    }

    func removeProtectedPath(_ url: URL) {
        customProtectedPaths.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        save(customProtectedPaths, key: Key.customProtectedPaths)
    }

    private func save(_ urls: [URL], key: String) {
        defaults.set(try? JSONEncoder().encode(urls), forKey: key)
    }

    private static func decodeURLs(_ data: Data?) -> [URL] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([URL].self, from: data)) ?? []
    }
}
