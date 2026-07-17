import Foundation
import XCTest
@testable import LazyestCleaner

final class LiveScanBenchmarkTests: XCTestCase {
    func testLiveFullScanTimings() async throws {
        guard ProcessInfo.processInfo.environment["TIDYMAC_LIVE_SCAN_BENCHMARK"] == "1" else {
            throw XCTSkip("Set TIDYMAC_LIVE_SCAN_BENCHMARK=1 to scan the current Mac.")
        }

        let coordinator = ScanCoordinator()
        let preferences = CleanupPreferences()
        let policy = ProtectionPolicy()
        let categories: [CleanupCategory] = [
            .caches,
            .browserData,
            .developerData,
            .logs,
            .applications,
            .systemApplications,
            .leftovers,
            .largeFiles,
            .oldFiles,
            .duplicates,
            .downloads,
            .desktopMedia,
            .docker,
            .trash,
        ]

        _ = await coordinator.beginScan()
        let fullScanStartedAt = Date()
        for category in categories {
            let startedAt = Date()
            do {
                let items = try await coordinator.scan(
                    category: category,
                    preferences: preferences,
                    policy: policy
                )
                let bytes = items.reduce(Int64(0)) { $0 + $1.size }
                print(
                    "LIVE_SCAN|\(category.rawValue)|"
                        + String(format: "%.3f", Date().timeIntervalSince(startedAt))
                        + "|\(items.count)|\(bytes)"
                )
            } catch {
                print(
                    "LIVE_SCAN|\(category.rawValue)|"
                        + String(format: "%.3f", Date().timeIntervalSince(startedAt))
                        + "|ERROR|\(error.localizedDescription)"
                )
            }
        }

        let total = Date().timeIntervalSince(fullScanStartedAt)
        print("LIVE_SCAN|total|" + String(format: "%.3f", total))
        XCTAssertLessThan(total, 30)
    }
}
