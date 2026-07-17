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
}
