import Foundation

protocol DockerDaemonProbing: Sendable {
    func check(executable: URL) async throws
}

enum DockerDaemonEndpoint {
    static func unixSocketPath(from endpoint: String) -> String? {
        let value = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.lowercased().hasPrefix("unix://") else { return nil }
        let encodedPath = String(value.dropFirst("unix://".count))
        let path = encodedPath.removingPercentEncoding ?? encodedPath
        return path.isEmpty ? nil : path
    }
}

actor DockerDaemonProbe: DockerDaemonProbing {
    static let contextTimeout: TimeInterval = 0.75
    static let pingTimeout: TimeInterval = 1

    private let runner: any ProcessRunning
    private let fileManager: FileManager
    private let home: URL
    private let dockerHost: String?
    private let curlExecutable: URL?

    init(
        runner: any ProcessRunning = ProcessRunner(),
        home: URL? = nil,
        dockerHost: String? = ProcessInfo.processInfo.environment["DOCKER_HOST"],
        curlExecutable: URL? = URL(fileURLWithPath: "/usr/bin/curl")
    ) {
        self.runner = runner
        self.fileManager = .default
        self.home = home ?? FileManager.default.homeDirectoryForCurrentUser
        self.dockerHost = dockerHost?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.curlExecutable = curlExecutable.flatMap {
            FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil
        }
    }

    func check(executable: URL) async throws {
        try Task.checkCancellation()

        if let dockerHost, !dockerHost.isEmpty {
            if let socketPath = DockerDaemonEndpoint.unixSocketPath(from: dockerHost) {
                try await pingUnixSocket(socketPath)
            } else {
                try await checkThroughDockerCLI(executable: executable)
            }
            return
        }

        if let socketPath = conventionalSocketPaths.first(where: {
            fileManager.fileExists(atPath: $0)
        }) {
            try await pingUnixSocket(socketPath)
            return
        }

        if let endpoint = try await resolveEndpoint(executable: executable),
            let socketPath = DockerDaemonEndpoint.unixSocketPath(from: endpoint)
        {
            try await pingUnixSocket(socketPath)
            return
        }

        try await checkThroughDockerCLI(executable: executable)
    }

    private func resolveEndpoint(executable: URL) async throws -> String? {
        if let dockerHost, !dockerHost.isEmpty {
            return dockerHost
        }

        do {
            let result = try await runner.run(
                executable: executable,
                arguments: ["context", "inspect", "--format", "{{.Endpoints.docker.Host}}"],
                timeout: Self.contextTimeout
            )
            guard result.exitCode == 0 else { return nil }
            return result.stdout
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func pingUnixSocket(_ socketPath: String) async throws {
        guard fileManager.fileExists(atPath: socketPath), let curlExecutable else {
            throw DockerServiceError.daemonUnavailable
        }

        do {
            let result = try await runner.run(
                executable: curlExecutable,
                arguments: [
                    "--silent",
                    "--show-error",
                    "--connect-timeout", "0.5",
                    "--max-time", "0.75",
                    "--unix-socket", socketPath,
                    "http://localhost/_ping",
                ],
                timeout: Self.pingTimeout
            )
            let response = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.exitCode == 0, response == "OK" else {
                throw DockerServiceError.daemonUnavailable
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DockerServiceError.daemonUnavailable
        }
    }

    private func checkThroughDockerCLI(executable: URL) async throws {
        do {
            let result = try await runner.run(
                executable: executable,
                arguments: ["version", "--format", "{{.Server.Version}}"],
                timeout: Self.pingTimeout
            )
            guard result.exitCode == 0,
                !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw DockerServiceError.daemonUnavailable
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DockerServiceError.daemonUnavailable
        }
    }

    private var conventionalSocketPaths: [String] {
        [
            home.appending(path: ".docker/run/docker.sock").path,
            "/var/run/docker.sock",
            home.appending(path: ".colima/default/docker.sock").path,
            home.appending(path: ".orbstack/run/docker.sock").path,
            home.appending(path: ".rd/docker.sock").path,
        ]
    }
}
