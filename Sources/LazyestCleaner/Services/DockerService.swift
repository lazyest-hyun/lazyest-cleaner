import Foundation

struct DockerDiskUsageRow: Decodable, Sendable {
    let type: String
    let totalCount: String
    let active: String
    let size: String
    let reclaimable: String

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case totalCount = "TotalCount"
        case active = "Active"
        case size = "Size"
        case reclaimable = "Reclaimable"
    }
}

enum DockerDiskUsageParser {
    static func parse(_ output: String) throws -> [DockerDiskUsageRow] {
        let rows =
            output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                try? JSONDecoder().decode(DockerDiskUsageRow.self, from: Data(line.utf8))
            }
        guard !rows.isEmpty || output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DockerServiceError.invalidResponse
        }
        return rows
    }
}

enum DockerServiceError: LocalizedError, Sendable {
    case unavailable
    case daemonUnavailable
    case commandFailed(String)
    case invalidResponse
    case timedOut(Int)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Docker를 찾을 수 없음"
        case .daemonUnavailable: "Docker 엔진에 연결할 수 없음"
        case let .commandFailed(message): message.isEmpty ? "Docker 명령 실패" : message
        case .invalidResponse: "Docker 응답을 읽을 수 없음"
        case let .timedOut(seconds): "Docker가 \(seconds)초 안에 응답하지 않음"
        }
    }
}

actor DockerService {
    static let scanTimeout: TimeInterval = 15
    static let pruneTimeout: TimeInterval = 300

    private let runner: any ProcessRunning
    private let executable: URL?
    private let daemonProbe: any DockerDaemonProbing

    init(
        runner: any ProcessRunning = ProcessRunner(),
        executable: URL? = ProcessRunner.locate("docker"),
        daemonProbe: (any DockerDaemonProbing)? = nil
    ) {
        self.runner = runner
        self.executable = executable
        self.daemonProbe = daemonProbe ?? DockerDaemonProbe(runner: runner)
    }

    func scan(preferences: CleanupPreferences) async throws -> [CleanupItem] {
        guard let executable else {
            throw DockerServiceError.unavailable
        }
        try await daemonProbe.check(executable: executable)
        let result = try await run(
            executable: executable,
            arguments: ["system", "df", "--format", "{{json .}}"],
            timeout: Self.scanTimeout
        )
        guard result.exitCode == 0 else {
            throw DockerServiceError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let rows = try DockerDiskUsageParser.parse(result.stdout)

        return rows.compactMap { row in
            guard let target = DockerPruneTarget(dockerDiskUsageType: row.type) else { return nil }
            let reclaimable = ByteSizeParser.parse(row.reclaimable) ?? 0
            guard reclaimable > 0 else { return nil }
            let isBlockedVolume = target == .volumes && !preferences.includeDockerVolumes
            let risk: CleanupRisk
            let recommendation: CleanupRecommendation
            switch target {
            case .buildCache:
                risk = .safe
                recommendation = .recommended
            case .images, .containers:
                risk = .review
                recommendation = .optional
            case .volumes:
                risk = isBlockedVolume ? .protected : .sensitive
                recommendation = .avoid
            case .system:
                risk = .sensitive
                recommendation = .avoid
            }
            let kind: CleanupItemKind =
                switch target {
                case .images: .dockerImage
                case .containers: .dockerContainer
                case .volumes: .dockerVolume
                case .buildCache, .system: .dockerBuildCache
                }
            return CleanupItem(
                id: "docker:\(target.rawValue)",
                category: .docker,
                kind: kind,
                name: target.title,
                url: nil,
                size: reclaimable,
                modifiedAt: nil,
                risk: risk,
                recommendation: recommendation,
                operation: .docker(target),
                source: "Docker",
                detail: nil,
                protectedReason: isBlockedVolume ? "볼륨 제외 설정" : nil,
                bundleIdentifier: nil,
                duplicateGroupID: nil,
                metadata: [
                    "전체": row.totalCount,
                    "사용 중": row.active,
                    "크기": row.size,
                    "회수 가능": row.reclaimable,
                ]
            )
        }
    }

    func prune(_ target: DockerPruneTarget) async throws -> ProcessResult {
        guard let executable else {
            throw DockerServiceError.unavailable
        }
        try await daemonProbe.check(executable: executable)
        let result = try await run(
            executable: executable,
            arguments: target.pruneArguments,
            timeout: Self.pruneTimeout
        )
        guard result.exitCode == 0 else {
            throw DockerServiceError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }

    private func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        do {
            return try await runner.run(
                executable: executable,
                arguments: arguments,
                timeout: timeout
            )
        } catch ProcessRunnerError.timedOut {
            throw DockerServiceError.timedOut(Int(timeout))
        } catch {
            throw DockerServiceError.commandFailed(error.localizedDescription)
        }
    }

}

extension DockerPruneTarget {
    init?(dockerDiskUsageType type: String) {
        switch type.lowercased() {
        case "images": self = .images
        case "containers": self = .containers
        case "local volumes", "volumes": self = .volumes
        case "build cache": self = .buildCache
        default: return nil
        }
    }

    var pruneArguments: [String] {
        switch self {
        case .images: ["image", "prune", "-a", "-f"]
        case .containers: ["container", "prune", "-f"]
        case .buildCache: ["builder", "prune", "-a", "-f"]
        case .volumes: ["volume", "prune", "-f"]
        case .system: ["system", "prune", "-a", "-f"]
        }
    }
}
