import Foundation
import XCTest
@testable import LazyestCleaner

final class DirectoryAccessServiceTests: XCTestCase {
    func testDeniedProbeIsBoundedAndCached() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let runner = TimedOutDirectoryProbeRunner()
        let service = DirectoryAccessService(
            runner: runner,
            executable: URL(fileURLWithPath: "/usr/bin/true")
        )

        let first = await service.canEnumerate(fixture)
        let cached = await service.canEnumerate(fixture)
        await service.invalidate()
        let refreshed = await service.canEnumerate(fixture)
        let calls = await runner.calls

        XCTAssertFalse(first)
        XCTAssertFalse(cached)
        XCTAssertFalse(refreshed)
        XCTAssertEqual(
            calls,
            [
                DirectoryAccessService.probeTimeout,
                DirectoryAccessService.probeTimeout,
            ])
    }
}

private actor TimedOutDirectoryProbeRunner: ProcessRunning {
    private(set) var calls: [TimeInterval] = []

    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        calls.append(timeout)
        throw ProcessRunnerError.timedOut
    }
}
