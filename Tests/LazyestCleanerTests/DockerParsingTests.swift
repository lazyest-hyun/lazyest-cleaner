import XCTest
@testable import LazyestCleaner

final class DockerParsingTests: XCTestCase {
    func testParsesDockerSystemDiskUsageJSONLines() throws {
        let output = """
            {"Type":"Images","TotalCount":"12","Active":"4","Size":"8.2GB","Reclaimable":"3.1GB (37%)"}
            {"Type":"Local Volumes","TotalCount":"8","Active":"6","Size":"4.0GB","Reclaimable":"512MB (12%)"}
            """
        let rows = try DockerDiskUsageParser.parse(output)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].type, "Images")
        XCTAssertEqual(ByteSizeParser.parse(rows[0].reclaimable), 3_100_000_000)
        XCTAssertEqual(rows[1].active, "6")
    }

    func testRejectsNonJSONResponse() {
        XCTAssertThrowsError(try DockerDiskUsageParser.parse("daemon unavailable")) { error in
            guard case DockerServiceError.invalidResponse = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testMapsDockerTypesAndPruneArguments() {
        XCTAssertEqual(DockerPruneTarget(dockerDiskUsageType: "Images"), .images)
        XCTAssertEqual(DockerPruneTarget(dockerDiskUsageType: "Local Volumes"), .volumes)
        XCTAssertNil(DockerPruneTarget(dockerDiskUsageType: "Unknown"))
        XCTAssertEqual(DockerPruneTarget.images.pruneArguments, ["image", "prune", "-a", "-f"])
        XCTAssertEqual(DockerPruneTarget.volumes.pruneArguments, ["volume", "prune", "-f"])
    }

    func testParsesUnixSocketEndpoint() {
        XCTAssertEqual(
            DockerDaemonEndpoint.unixSocketPath(from: "unix:///Users/test/.docker/run/docker.sock\n"),
            "/Users/test/.docker/run/docker.sock"
        )
        XCTAssertNil(DockerDaemonEndpoint.unixSocketPath(from: "tcp://127.0.0.1:2375"))
    }

    func testConventionalSocketSkipsDockerContextLookup() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let socket = fixture.appending(path: ".docker/run/docker.sock")
        try FileManager.default.createDirectory(
            at: socket.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: socket)

        let runner = DockerProbeRecordingRunner()
        let probe = DockerDaemonProbe(
            runner: runner,
            home: fixture,
            dockerHost: nil,
            curlExecutable: URL(fileURLWithPath: "/usr/bin/true")
        )
        try await probe.check(executable: URL(fileURLWithPath: "/usr/bin/false"))

        let calls = await runner.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls[0].arguments.contains("--unix-socket"))
        XCTAssertFalse(calls[0].arguments.contains("context"))
        XCTAssertEqual(calls[0].timeout, DockerDaemonProbe.pingTimeout)
    }

    func testUnavailableDaemonStopsBeforeDiskUsageCommand() async {
        let runner = DockerCallCountingRunner()
        let service = DockerService(
            runner: runner,
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            daemonProbe: UnavailableDockerDaemonProbe()
        )

        do {
            _ = try await service.scan(preferences: CleanupPreferences())
            XCTFail("expected unavailable daemon")
        } catch let error as DockerServiceError {
            guard case .daemonUnavailable = error else {
                return XCTFail("unexpected error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let callCount = await runner.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testTranslatesProcessTimeoutIntoDockerTimeout() async {
        let service = DockerService(
            runner: DockerTimeoutRunner(),
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            daemonProbe: ReadyDockerDaemonProbe()
        )

        do {
            _ = try await service.scan(preferences: CleanupPreferences())
            XCTFail("expected timeout")
        } catch let error as DockerServiceError {
            guard case let .timedOut(seconds) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(seconds, 15)
            XCTAssertEqual(error.localizedDescription, "Docker가 15초 안에 응답하지 않음")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

private actor DockerProbeRecordingRunner: ProcessRunning {
    struct Call: Sendable {
        let arguments: [String]
        let timeout: TimeInterval
    }

    private(set) var calls: [Call] = []

    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        calls.append(Call(arguments: arguments, timeout: timeout))
        return ProcessResult(exitCode: 0, stdout: "OK", stderr: "")
    }
}

private struct ReadyDockerDaemonProbe: DockerDaemonProbing {
    func check(executable: URL) async throws {}
}

private struct UnavailableDockerDaemonProbe: DockerDaemonProbing {
    func check(executable: URL) async throws {
        throw DockerServiceError.daemonUnavailable
    }
}

private actor DockerCallCountingRunner: ProcessRunning {
    private(set) var callCount = 0

    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        callCount += 1
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

private struct DockerTimeoutRunner: ProcessRunning {
    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        guard timeout == DockerService.scanTimeout else {
            throw ProcessRunnerError.launchFailed("unexpected timeout")
        }
        throw ProcessRunnerError.timedOut
    }
}
