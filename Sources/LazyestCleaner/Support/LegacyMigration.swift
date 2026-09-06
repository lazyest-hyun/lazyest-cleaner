import Foundation

/// Historical identifiers exist only here to retain existing user preferences and history.
enum LegacyMigration {
    static let historyPaths = ["Lazyest Tidy/history.json", "TidyMac/history.json"]
    private static let preferenceDomain = "com.tidymac.cleaner"
    private static let marker = "migration.brandPreferences.v1"
    private static let preferenceKeys = [
        "settings.autoScan", "settings.includeHiddenFiles", "settings.allowImmediateRemoval",
        "settings.includeDockerVolumes", "settings.includeSystemApplicationsInFullScan",
        "settings.includeDockerInFullScan", "settings.largeFileThreshold", "settings.oldFileDays",
        "settings.duplicateMinimumSize", "settings.customScanRoots", "settings.customProtectedPaths",
    ]

    static func migratePreferences(to defaults: UserDefaults, legacyValues: [String: Any]? = nil) {
        guard !defaults.bool(forKey: marker) else { return }
        let values = legacyValues ?? defaults.persistentDomain(forName: preferenceDomain) ?? [:]
        for key in preferenceKeys where defaults.object(forKey: key) == nil {
            if let value = values[key] { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: marker)
    }
}
