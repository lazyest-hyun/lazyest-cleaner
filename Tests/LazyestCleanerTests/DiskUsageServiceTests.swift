import Foundation
import XCTest
@testable import LazyestCleaner

final class DiskUsageServiceTests: XCTestCase {
    func testRetriesUnresolvedPathsAndThenUsesFreshCache() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let first = fixture.appending(path: "First Cache")
        let second = fixture.appending(path: "Second Cache")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        let runner = PartialDiskUsageRunner()
        let service = DiskUsageService(
            home: fixture,
            runner: runner,
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            cacheURL: fixture.appending(path: "disk-usage.json")
        )

        let initial = try await service.sizes(of: [first, second])
        let cached = try await service.sizes(of: [first, second])
        let callCount = await runner.callCount
        let timeouts = await runner.timeouts

        XCTAssertEqual(initial[first.standardizedFileURL.path], 1_024)
        XCTAssertEqual(initial[second.standardizedFileURL.path], 2_048)
        XCTAssertEqual(cached, initial)
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(
            timeouts,
            [
                DiskUsageService.batchTimeout,
                DiskUsageService.individualTimeout,
            ])
    }

    func testUnresolvedPathUsesNegativeCacheOnNextScan() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let candidate = fixture.appending(path: "Slow Cache")
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)

        let runner = AlwaysTimeoutDiskUsageRunner()
        let service = DiskUsageService(
            home: fixture,
            runner: runner,
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            cacheURL: fixture.appending(path: "negative-cache.json")
        )

        let initial = try await service.sizes(of: [candidate])
        let cached = try await service.sizes(of: [candidate])
        let callCount = await runner.callCount

        XCTAssertNil(initial[candidate.standardizedFileURL.path])
        XCTAssertEqual(cached[candidate.standardizedFileURL.path], 0)
        XCTAssertEqual(callCount, 2)
    }
}

private actor AlwaysTimeoutDiskUsageRunner: ProcessRunning {
    private(set) var callCount = 0

    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        callCount += 1
        throw ProcessRunnerError.timedOut
    }
}

private actor PartialDiskUsageRunner: ProcessRunning {
    private(set) var callCount = 0
    private(set) var timeouts: [TimeInterval] = []

    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        callCount += 1
        timeouts.append(timeout)
        let paths = Array(arguments.dropFirst())
        if paths.count > 1 {
            return ProcessResult(
                exitCode: 1,
                stdout: "1\t\(paths[0])\n",
                stderr: "partial"
            )
        }
        return ProcessResult(
            exitCode: 0,
            stdout: "2\t\(paths[0])\n",
            stderr: ""
        )
    }
}
