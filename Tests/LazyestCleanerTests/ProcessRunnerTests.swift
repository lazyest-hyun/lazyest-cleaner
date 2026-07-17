import Foundation
import XCTest
@testable import LazyestCleaner

final class ProcessRunnerTests: XCTestCase {
    func testCapturesStandardOutput() async throws {
        let result = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["hello"],
            timeout: 2
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "hello")
        XCTAssertEqual(result.stderr, "")
    }

    func testTerminatesTimedOutProcess() async {
        let startedAt = Date()
        defer { XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5) }
        do {
            _ = try await ProcessRunner().run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"],
                timeout: 0.05
            )
            XCTFail("timeout expected")
        } catch ProcessRunnerError.timedOut {
            XCTAssertTrue(true)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
