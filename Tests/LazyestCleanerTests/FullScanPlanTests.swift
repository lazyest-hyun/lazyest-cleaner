import XCTest
@testable import LazyestCleaner

final class FullScanPlanTests: XCTestCase {
    func testDefaultPlanSkipsSlowOrReadOnlyOptionalSources() {
        let categories = FullScanPlan(
            includeSystemApplications: false,
            includeDocker: false,
            includeCustomLocations: false
        ).categories

        XCTAssertFalse(categories.contains(.systemApplications))
        XCTAssertFalse(categories.contains(.docker))
        XCTAssertFalse(categories.contains(.custom))
        XCTAssertTrue(categories.contains(.applications))
        XCTAssertTrue(categories.contains(.trash))
    }

    func testOptionalSourcesAreInsertedInTheirOwningWorkspaces() {
        let categories = FullScanPlan(
            includeSystemApplications: true,
            includeDocker: true,
            includeCustomLocations: true
        ).categories

        XCTAssertEqual(
            categories.firstIndex(of: .systemApplications),
            categories.firstIndex(of: .applications).map { $0 + 1 }
        )
        XCTAssertEqual(
            categories.firstIndex(of: .docker),
            categories.firstIndex(of: .developerData).map { $0 + 1 }
        )
        XCTAssertEqual(categories.last, .custom)
        XCTAssertEqual(Set(categories).count, categories.count)
    }
}
