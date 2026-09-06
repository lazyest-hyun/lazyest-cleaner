import Foundation
import XCTest
@testable import LazyestCleaner

@MainActor
final class AppSettingsTests: XCTestCase {
    func testOptionalFullScanSourcesDefaultOffAndPersist() {
        let suiteName = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = AppSettings(defaults: defaults)
        XCTAssertFalse(initial.autoScan)
        XCTAssertFalse(initial.includeSystemApplicationsInFullScan)
        XCTAssertFalse(initial.includeDockerInFullScan)

        initial.includeSystemApplicationsInFullScan = true
        initial.includeDockerInFullScan = true

        let restored = AppSettings(defaults: defaults)
        XCTAssertTrue(restored.includeSystemApplicationsInFullScan)
        XCTAssertTrue(restored.includeDockerInFullScan)
        XCTAssertTrue(restored.snapshot.includeSystemApplicationsInFullScan)
        XCTAssertTrue(restored.snapshot.includeDockerInFullScan)
    }
    func testLegacyPreferencesPreserveProtectionAndExistingValuesOnlyOnce() {
        let suiteName = "MigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "settings.autoScan")
        let protected = try! JSONEncoder().encode([URL(fileURLWithPath: "/example/protected")])
        LegacyMigration.migratePreferences(
            to: defaults,
            legacyValues: [
                "settings.autoScan": true,
                "settings.customProtectedPaths": protected,
                "unrelated.private.value": "must not migrate",
            ])
        XCTAssertFalse(defaults.bool(forKey: "settings.autoScan"))
        XCTAssertEqual(AppSettings(defaults: defaults).customProtectedPaths.count, 1)
        XCTAssertNil(defaults.object(forKey: "unrelated.private.value"))
        defaults.removeObject(forKey: "settings.customProtectedPaths")
        LegacyMigration.migratePreferences(to: defaults, legacyValues: ["settings.customProtectedPaths": protected])
        XCTAssertNil(defaults.object(forKey: "settings.customProtectedPaths"))
    }
}
