import AppKit
import Foundation

protocol FileRecycling: Sendable {
    func recycle(_ urls: [URL]) async throws -> [URL: URL]
}

struct WorkspaceRecycler: FileRecycling {
    func recycle(_ urls: [URL]) async throws -> [URL: URL] {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                NSWorkspace.shared.recycle(urls) { mapping, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: mapping)
                    }
                }
            }
        }
    }
}

enum CleanupPreflight {
    static func failureReason(
        for item: CleanupItem,
        action: CleanupActionID,
        preferences: CleanupPreferences,
        policy: ProtectionPolicy,
        homeURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        if item.isProtected {
            return item.protectedReason ?? "보호 항목"
        }
        if case .docker = item.operation {
            return action == .runDockerCleanup ? nil : "Docker 전용 액션 필요"
        }
        guard let url = item.url else { return "경로 없음" }
        guard fileManager.fileExists(atPath: url.path) else { return "항목 없음" }
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values?.isSymbolicLink == true { return "심볼릭 링크" }
        if let reason = policy.decision(for: url, bundleIdentifier: item.bundleIdentifier).reason {
            return reason
        }
        let home = (homeURL ?? fileManager.homeDirectoryForCurrentUser).standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let allowed = path.hasPrefix("\(home)/") || path.hasPrefix("/Applications/")
        if !allowed { return "허용 범위 밖" }

        switch action {
        case .moveToTrash:
            if item.kind == .trash { return "이미 휴지통" }
            if item.kind == .application { return "앱 전용 액션 필요" }
        case .removeApplicationOnly:
            if item.kind != .application { return "앱만 가능" }
        case .removeAppData:
            if item.kind != .appLeftover { return "앱 데이터만 가능" }
        case .uninstallApplication:
            if ![.application, .appLeftover].contains(item.kind) { return "앱 제거 항목 아님" }
        case .deletePermanently:
            if item.kind != .trash { return "휴지통 항목만 가능" }
        case .removeImmediately:
            let allowedKinds: Set<CleanupItemKind> = [.cache, .browserCache, .developerCache, .log]
            if !allowedKinds.contains(item.kind) { return "즉시 삭제 불가" }
            if !preferences.allowImmediateRemoval { return "즉시 삭제 꺼짐" }
        default:
            break
        }
        return nil
    }
}

actor CleanupExecutor {
    private let fileManager: FileManager
    private let recycler: any FileRecycling
    private let dockerService: DockerService

    init(
        fileManager: FileManager = .default,
        recycler: any FileRecycling = WorkspaceRecycler(),
        dockerService: DockerService = DockerService()
    ) {
        self.fileManager = fileManager
        self.recycler = recycler
        self.dockerService = dockerService
    }

    func execute(
        action: CleanupActionID,
        items: [CleanupItem],
        preferences: CleanupPreferences,
        policy: ProtectionPolicy
    ) async -> CleanupExecutionReport {
        var failures: [CleanupExecutionFailure] = []
        var executableItems: [CleanupItem] = []
        var runningApplications: [String: Bool] = [:]

        for item in items {
            if let reason = CleanupPreflight.failureReason(
                for: item,
                action: action,
                preferences: preferences,
                policy: policy,
                fileManager: fileManager
            ) {
                failures.append(.init(itemID: item.id, name: item.name, reason: reason))
                continue
            }
            let requiresStoppedApplication =
                item.kind == .application
                || action == .removeAppData
                || action == .uninstallApplication
            if requiresStoppedApplication,
                let bundleIdentifier = item.bundleIdentifier
            {
                let isRunning: Bool
                if let cached = runningApplications[bundleIdentifier] {
                    isRunning = cached
                } else {
                    isRunning = await isApplicationRunning(bundleIdentifier)
                    runningApplications[bundleIdentifier] = isRunning
                }
                if isRunning {
                    failures.append(.init(itemID: item.id, name: item.name, reason: "앱 실행 중"))
                    continue
                }
            }
            executableItems.append(item)
        }

        let outcome: (succeeded: Int, failures: [CleanupExecutionFailure])
        switch action {
        case .moveToTrash, .removeApplicationOnly, .removeAppData, .uninstallApplication:
            outcome = await recycle(executableItems)
        case .removeImmediately, .deletePermanently:
            outcome = removeImmediately(executableItems)
        case .runDockerCleanup:
            outcome = await pruneDocker(executableItems)
        default:
            outcome = (
                0,
                executableItems.map {
                    .init(itemID: $0.id, name: $0.name, reason: "실행 액션 아님")
                }
            )
        }
        failures.append(contentsOf: outcome.failures)

        return CleanupExecutionReport(
            action: action,
            itemCount: items.count,
            bytes: items.reduce(0) { $0 + $1.size },
            succeeded: outcome.succeeded,
            failures: failures
        )
    }

    private func recycle(_ items: [CleanupItem]) async -> (
        succeeded: Int,
        failures: [CleanupExecutionFailure]
    ) {
        let urls = minimizedURLs(items.compactMap(\.url))
        guard !urls.isEmpty else { return (0, []) }
        do {
            let mapping = try await recycler.recycle(urls)
            let recycledRoots = mapping.keys.map(\.standardizedFileURL.path)
            let succeededItems = items.filter { item in
                guard let path = item.url?.standardizedFileURL.path else { return false }
                return recycledRoots.contains { root in
                    path == root || path.hasPrefix(root + "/")
                }
            }
            let succeededIDs = Set(succeededItems.map(\.id))
            let failures = items.compactMap { item -> CleanupExecutionFailure? in
                guard !succeededIDs.contains(item.id) else { return nil }
                return CleanupExecutionFailure(
                    itemID: item.id,
                    name: item.name,
                    reason: "휴지통 이동을 확인할 수 없음"
                )
            }
            return (succeededItems.count, failures)
        } catch {
            return (
                0,
                items.map {
                    .init(itemID: $0.id, name: $0.name, reason: error.localizedDescription)
                }
            )
        }
    }

    private func removeImmediately(_ items: [CleanupItem]) -> (
        succeeded: Int,
        failures: [CleanupExecutionFailure]
    ) {
        var succeeded = 0
        var failures: [CleanupExecutionFailure] = []
        for item in items {
            guard let url = item.url else { continue }
            do {
                try fileManager.removeItem(at: url)
                succeeded += 1
            } catch {
                failures.append(.init(itemID: item.id, name: item.name, reason: error.localizedDescription))
            }
        }
        return (succeeded, failures)
    }

    private func pruneDocker(_ items: [CleanupItem]) async -> (
        succeeded: Int,
        failures: [CleanupExecutionFailure]
    ) {
        var succeeded = 0
        var failures: [CleanupExecutionFailure] = []
        var seen = Set<DockerPruneTarget>()
        for item in items {
            guard case let .docker(target) = item.operation, seen.insert(target).inserted else { continue }
            do {
                _ = try await dockerService.prune(target)
                succeeded += 1
            } catch {
                failures.append(.init(itemID: item.id, name: item.name, reason: error.localizedDescription))
            }
        }
        return (succeeded, failures)
    }

    private func minimizedURLs(_ urls: [URL]) -> [URL] {
        let sorted = urls.map(\.standardizedFileURL).sorted { $0.path.count < $1.path.count }
        var result: [URL] = []
        for url in sorted {
            let path = url.path
            if result.contains(where: { path.hasPrefix("\($0.path)/") }) { continue }
            result.append(url)
        }
        return result
    }

    private func isApplicationRunning(_ bundleIdentifier: String) async -> Bool {
        await MainActor.run {
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        }
    }
}
