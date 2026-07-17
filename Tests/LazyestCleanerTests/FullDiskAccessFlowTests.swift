import Foundation
import XCTest
@testable import LazyestCleaner

final class FullDiskAccessFlowTests: XCTestCase {
    func testRestrictedCategoriesStopBeforeFolderScan() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let access = MutableDirectoryAccess(granted: false)
        let coordinator = ScanCoordinator(
            directoryAccess: access,
            fullDiskAccessProbeURL: fixture
        )

        let granted = await coordinator.beginScan()
        XCTAssertFalse(granted)

        let restrictedCategories: [CleanupCategory] = [
            .leftovers,
            .largeFiles,
            .oldFiles,
            .duplicates,
            .downloads,
            .desktopMedia,
            .trash,
        ]
        for category in restrictedCategories {
            do {
                _ = try await coordinator.scan(
                    category: category,
                    preferences: CleanupPreferences(),
                    policy: ProtectionPolicy(home: fixture)
                )
                XCTFail("expected full disk access error for \(category)")
            } catch FullDiskAccessError.required {
                continue
            } catch {
                XCTFail("unexpected error for \(category): \(error)")
            }
        }

        let probes = await access.probes
        XCTAssertEqual(probes, [fixture.standardizedFileURL.path])
    }

    func testRefreshInvalidatesDeniedStateAndRecognizesGrant() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let access = MutableDirectoryAccess(granted: false)
        let coordinator = ScanCoordinator(
            directoryAccess: access,
            fullDiskAccessProbeURL: fixture
        )

        let initiallyGranted = await coordinator.beginScan()
        XCTAssertFalse(initiallyGranted)
        await access.setGranted(true)
        let refreshedGrant = await coordinator.refreshFullDiskAccess()
        XCTAssertTrue(refreshedGrant)

        let invalidations = await access.invalidationCount
        let probes = await access.probes
        XCTAssertEqual(invalidations, 1)
        XCTAssertEqual(probes.count, 2)
    }
}

private actor MutableDirectoryAccess: DirectoryAccessChecking {
    private var granted: Bool
    private(set) var probes: [String] = []
    private(set) var invalidationCount = 0

    init(granted: Bool) {
        self.granted = granted
    }

    func canEnumerate(_ url: URL) async -> Bool {
        probes.append(url.standardizedFileURL.path)
        return granted
    }

    func invalidate() async {
        invalidationCount += 1
    }

    func setGranted(_ granted: Bool) {
        self.granted = granted
    }
}
