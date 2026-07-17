import Foundation
import XCTest
@testable import LazyestCleaner

final class ApplicationSizeServiceTests: XCTestCase {
    func testParsesBatchDiskUsageWithSpacesInPaths() {
        let output = """
            2048\t/Applications/My App.app
            malformed
            512\t/System/Applications/Music.app
            """

        let sizes = DiskUsageOutputParser.parse(output)

        XCTAssertEqual(sizes["/Applications/My App.app"], 2_097_152)
        XCTAssertEqual(sizes["/System/Applications/Music.app"], 524_288)
        XCTAssertEqual(sizes.count, 2)
    }

    func testPersistsAndReusesUnchangedApplicationSize() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = fixture.appending(path: "My App.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let modifiedAt = Date(timeIntervalSinceReferenceDate: 123_456)
        let cacheURL = fixture.appending(path: "sizes.json")
        let output = "4096\t\(app.standardizedFileURL.path)\n"

        let firstRunner = DiskUsageRunner(output: output)
        let firstService = ApplicationSizeService(
            home: fixture,
            fileScanner: FileScanner(home: fixture),
            runner: firstRunner,
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            cacheURL: cacheURL
        )
        let request = ApplicationSizeRequest(url: app, modifiedAt: modifiedAt)
        let first = try await firstService.sizes(for: [request])

        let secondRunner = DiskUsageRunner(output: "8192\t\(app.path)\n")
        let secondService = ApplicationSizeService(
            home: fixture,
            fileScanner: FileScanner(home: fixture),
            runner: secondRunner,
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            cacheURL: cacheURL
        )
        let second = try await secondService.sizes(for: [request])
        let firstCalls = await firstRunner.callCount
        let secondCalls = await secondRunner.callCount

        XCTAssertEqual(first[request.path], 4_194_304)
        XCTAssertEqual(second[request.path], 4_194_304)
        XCTAssertEqual(firstCalls, 1)
        XCTAssertEqual(secondCalls, 0)
    }

    func testTimedOutApplicationUsesBoundedNegativeCache() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = fixture.appending(path: "Slow.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let runner = TimedOutApplicationSizeRunner()
        let service = ApplicationSizeService(
            home: fixture,
            fileScanner: FileScanner(home: fixture),
            runner: runner,
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            cacheURL: fixture.appending(path: "timed-out-sizes.json")
        )
        let request = ApplicationSizeRequest(url: app, modifiedAt: Date())

        let initial = try await service.sizes(for: [request])
        let cached = try await service.sizes(for: [request])
        let timeouts = await runner.timeouts

        XCTAssertEqual(initial[request.path], 0)
        XCTAssertEqual(cached[request.path], 0)
        XCTAssertEqual(
            timeouts,
            [
                ApplicationSizeService.batchTimeout,
                ApplicationSizeService.individualTimeout,
            ])
    }
}

private actor TimedOutApplicationSizeRunner: ProcessRunning {
    private(set) var timeouts: [TimeInterval] = []

    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        timeouts.append(timeout)
        throw ProcessRunnerError.timedOut
    }
}

private actor DiskUsageRunner: ProcessRunning {
    private(set) var callCount = 0
    private let output: String

    init(output: String) {
        self.output = output
    }

    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        callCount += 1
        return ProcessResult(exitCode: 0, stdout: output, stderr: "")
    }
}
