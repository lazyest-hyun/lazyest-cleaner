import Darwin
import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ProcessRunnerError: LocalizedError, Sendable {
    case executableNotFound(String)
    case launchFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case let .executableNotFound(name): "\(name)을 찾을 수 없음"
        case let .launchFailed(message): message
        case .timedOut: "명령 시간 초과"
        }
    }
}

protocol ProcessRunning: Sendable {
    func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult
}

struct ProcessRunner: ProcessRunning, Sendable {
    func run(executable: URL, arguments: [String], timeout: TimeInterval = 10) async throws -> ProcessResult {
        let execution = ProcessExecution(executable: executable, arguments: arguments, timeout: timeout)
        return try await execution.run()
    }

    static func locate(_ name: String) -> URL? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/Applications/Docker.app/Contents/Resources/bin/\(name)",
        ]
        return
            candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private final class ProcessExecution: @unchecked Sendable {
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProcessResult, any Error>?
    private var didFinish = false
    private var didTimeOut = false

    init(executable: URL, arguments: [String], timeout: TimeInterval) {
        self.timeout = timeout
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice
    }

    func run() async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            lock.synchronized {
                self.continuation = continuation
            }
            process.terminationHandler = { [self] process in
                complete(exitCode: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                complete(error: ProcessRunnerError.launchFailed(error.localizedDescription))
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.terminateForTimeout()
            }
        }
    }

    private func terminateForTimeout() {
        let shouldTimeOut = lock.synchronized {
            guard !didFinish else { return false }
            didTimeOut = true
            return true
        }
        guard shouldTimeOut else { return }

        let process = process
        let pid = process.processIdentifier
        complete(error: ProcessRunnerError.timedOut)
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            guard process.isRunning else { return }
            Darwin.kill(pid, SIGKILL)
        }
    }

    private func complete(exitCode: Int32) {
        let state = lock.synchronized { () -> (CheckedContinuation<ProcessResult, any Error>?, Bool)? in
            guard !didFinish else { return nil }
            didFinish = true
            let pendingContinuation = self.continuation
            self.continuation = nil
            return (pendingContinuation, didTimeOut)
        }
        guard let state else { return }
        process.terminationHandler = nil
        if state.1 {
            state.0?.resume(throwing: ProcessRunnerError.timedOut)
            return
        }

        let output = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errors = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let result = ProcessResult(
            exitCode: exitCode,
            stdout: String(decoding: output, as: UTF8.self),
            stderr: String(decoding: errors, as: UTF8.self)
        )

        state.0?.resume(returning: result)
    }

    private func complete(error: any Error) {
        let continuation = lock.synchronized { () -> CheckedContinuation<ProcessResult, any Error>? in
            guard !didFinish else { return nil }
            didFinish = true
            let pendingContinuation = self.continuation
            self.continuation = nil
            return pendingContinuation
        }
        process.terminationHandler = nil
        continuation?.resume(throwing: error)
    }
}

private extension NSLock {
    func synchronized<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
