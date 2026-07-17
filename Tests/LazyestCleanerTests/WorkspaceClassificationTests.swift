import XCTest
@testable import LazyestCleaner

final class WorkspaceClassificationTests: XCTestCase {
    func testEveryCategoryBelongsToExactlyOneWorkspace() {
        let categories = CleanupWorkspace.allCases.flatMap(\.categories)

        XCTAssertEqual(categories.count, CleanupCategory.allCases.count)
        XCTAssertEqual(Set(categories), Set(CleanupCategory.allCases))
    }

    func testSettingsAndHistoryAreNonScanningDestinations() {
        XCTAssertFalse(CleanupWorkspace.settings.defaultCategory.supportsScan)
        XCTAssertFalse(CleanupWorkspace.history.defaultCategory.supportsScan)
        XCTAssertEqual(CleanupWorkspace.containing(.settings), .settings)
        XCTAssertEqual(CleanupWorkspace.containing(.history), .history)
    }

    func testDockerIsADeveloperTabAndSystemAppsStayInAppWorkspace() {
        XCTAssertEqual(CleanupWorkspace.developer.categories, [.developerData, .docker])
        XCTAssertEqual(
            CleanupWorkspace.applications.categories,
            [.applications, .systemApplications, .leftovers]
        )
        XCTAssertEqual(CleanupWorkspace.containing(.docker), .developer)
        XCTAssertEqual(CleanupWorkspace.containing(.systemApplications), .applications)
    }
}
