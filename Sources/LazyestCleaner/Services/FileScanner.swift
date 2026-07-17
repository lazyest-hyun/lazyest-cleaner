import AppKit
import Darwin
import Foundation

enum TrashAccessError: LocalizedError, Sendable {
    case permissionDenied
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "휴지통 접근 권한 필요"
        case let .unavailable(message): message.isEmpty ? "휴지통을 읽을 수 없음" : message
        }
    }
}

private struct BrowserRoot: Sendable {
    let name: String
    let bundleIdentifier: String
    let cachePaths: [String]
    let supportPaths: [String]
}

private struct BrowserCacheCandidate: Sendable {
    let url: URL
    let browserName: String
    let running: Bool
}

actor FileScanner {
    private let fileManager: FileManager
    private let home: URL
    private let diskUsage: any DiskUsageMeasuring
    private let fileInventory: FileInventoryService
    private let directoryAccess: any DirectoryAccessChecking
    private let minimumCandidateSize: Int64 = 1_000_000

    init(
        fileManager: FileManager = .default,
        home: URL? = nil,
        diskUsage: (any DiskUsageMeasuring)? = nil,
        fileInventory: FileInventoryService? = nil,
        directoryAccess: (any DirectoryAccessChecking)? = nil
    ) {
        self.fileManager = fileManager
        let resolvedHome = home ?? fileManager.homeDirectoryForCurrentUser
        let resolvedDirectoryAccess =
            directoryAccess
            ?? DirectoryAccessService()
        self.home = resolvedHome
        self.diskUsage = diskUsage ?? DiskUsageService(home: resolvedHome)
        self.fileInventory =
            fileInventory
            ?? FileInventoryService(
                directoryAccess: resolvedDirectoryAccess
            )
        self.directoryAccess = resolvedDirectoryAccess
    }

    func scan(
        category: CleanupCategory,
        preferences: CleanupPreferences,
        policy: ProtectionPolicy
    ) async throws -> [CleanupItem] {
        switch category {
        case .largeFiles:
            try await scanLargeFiles(preferences: preferences, policy: policy)
        case .oldFiles:
            try await scanOldFiles(preferences: preferences, policy: policy)
        case .downloads:
            try await scanDownloads(preferences: preferences, policy: policy)
        case .desktopMedia:
            try await scanDesktopMedia(preferences: preferences, policy: policy)
        case .caches:
            try await scanCaches(policy: policy)
        case .browserData:
            try await scanBrowserData(policy: policy)
        case .developerData:
            try await scanDeveloperData(policy: policy)
        case .logs:
            try await scanLogs(policy: policy)
        case .trash:
            try await scanTrash(policy: policy)
        case .custom:
            try await scanCustom(preferences: preferences, policy: policy)
        default:
            []
        }
    }

    func allocatedSize(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: resourceKeys)
        if values.isSymbolicLink == true {
            return 0
        }
        if values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        guard values.isDirectory == true else { return 0 }

        var total: Int64 = 0
        guard
            let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            )
        else {
            return 0
        }
        var count = 0
        for case let child as URL in enumerator {
            count += 1
            if count.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            guard let childValues = try? child.resourceValues(forKeys: resourceKeys),
                childValues.isSymbolicLink != true,
                childValues.isRegularFile == true
            else {
                continue
            }
            total += Int64(
                childValues.totalFileAllocatedSize ?? childValues.fileAllocatedSize ?? childValues.fileSize ?? 0)
        }
        return total
    }

    func batchAllocatedSizes(of urls: [URL]) async throws -> [String: Int64] {
        try await diskUsage.sizes(of: urls)
    }

    private var resourceKeys: Set<URLResourceKey> {
        [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
        ]
    }

    private func scanLargeFiles(
        preferences: CleanupPreferences,
        policy: ProtectionPolicy
    ) async throws -> [CleanupItem] {
        let records = try await fileInventory.records(
            roots: defaultFileRoots,
            includeHiddenFiles: preferences.includeHiddenFiles,
            policy: policy
        )
        return
            records
            .filter { $0.size >= preferences.largeFileThreshold }
            .prefix(10_000)
            .compactMap { record in
                try? makeFileItem(
                    url: record.url,
                    category: .largeFiles,
                    kind: kind(for: record.url),
                    measuredSize: record.size,
                    risk: .review,
                    recommendation: .optional,
                    source: "대용량",
                    policy: policy
                )
            }
    }

    private func scanOldFiles(
        preferences: CleanupPreferences,
        policy: ProtectionPolicy
    ) async throws -> [CleanupItem] {
        let cutoff =
            Calendar.current.date(
                byAdding: .day,
                value: -preferences.oldFileDays,
                to: Date()
            ) ?? .distantPast
        let records = try await fileInventory.records(
            roots: defaultFileRoots,
            includeHiddenFiles: preferences.includeHiddenFiles,
            policy: policy
        )
        return
            records
            .filter {
                $0.size >= minimumCandidateSize
                    && ($0.modifiedAt ?? .distantFuture) < cutoff
            }
            .prefix(10_000)
            .compactMap { record in
                try? makeFileItem(
                    url: record.url,
                    category: .oldFiles,
                    kind: kind(for: record.url),
                    measuredSize: record.size,
                    risk: .review,
                    recommendation: .optional,
                    source: "오래된 파일",
                    policy: policy
                )
            }
    }

    private func scanDownloads(
        preferences: CleanupPreferences,
        policy: ProtectionPolicy
    ) async throws -> [CleanupItem] {
        let downloads = home.appending(path: "Downloads")
        guard await directoryAccess.canEnumerate(downloads) else {
            throw DirectoryAccessError.permissionDenied("다운로드")
        }
        let urls = try topLevelItems(
            at: downloads,
            includeHidden: preferences.includeHiddenFiles
        )
        let sizes = try await diskUsage.sizes(of: urls)
        return urls.compactMap { url in
            guard let size = sizes[url.standardizedFileURL.path],
                size >= minimumCandidateSize
            else { return nil }
            let fileKind = kind(for: url)
            let isInstaller = fileKind == .installer
            return try? makeFileItem(
                url: url,
                category: .downloads,
                kind: fileKind,
                measuredSize: size,
                risk: isInstaller ? .safe : .review,
                recommendation: isInstaller ? .recommended : .optional,
                source: "다운로드",
                policy: policy
            )
        }
    }

    private func scanDesktopMedia(
        preferences: CleanupPreferences,
        policy: ProtectionPolicy
    ) async throws -> [CleanupItem] {
        let extensions = Set(["mp4", "mov", "mkv", "avi", "webm", "m4v"])
        let desktop = home.appending(path: "Desktop")
        guard await directoryAccess.canEnumerate(desktop) else {
            throw DirectoryAccessError.permissionDenied("데스크톱")
        }
        let desktopPath = desktop.standardizedFileURL.path + "/"
        let records = try await fileInventory.records(
            roots: defaultFileRoots,
            includeHiddenFiles: preferences.includeHiddenFiles,
            policy: policy
        )
        return
            records
            .filter {
                $0.url.standardizedFileURL.path.hasPrefix(desktopPath)
                    && extensions.contains($0.url.pathExtension.lowercased())
            }
            .compactMap { record in
                try? makeFileItem(
                    url: record.url,
                    category: .desktopMedia,
                    kind: .file,
                    measuredSize: record.size,
                    risk: .review,
                    recommendation: .optional,
                    source: "데스크톱",
                    policy: policy
                )
            }
    }

    private func scanCaches(policy: ProtectionPolicy) async throws -> [CleanupItem] {
        let root = home.appending(path: "Library/Caches")
        let urls = try genericCacheCandidates(at: root)
        let sizes = try await diskUsage.sizes(of: urls)
        let runningBundleIdentifiers = await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
        return urls.compactMap { url in
            guard let size = sizes[url.standardizedFileURL.path],
                size >= minimumCandidateSize
            else { return nil }
            let isRunning = runningBundleIdentifiers.contains(url.lastPathComponent)
            return try? makeFileItem(
                url: url,
                category: .caches,
                kind: .cache,
                measuredSize: size,
                risk: isRunning ? .protected : .safe,
                recommendation: isRunning ? .avoid : .recommended,
                source: "앱 캐시",
                detail: isRunning ? "앱 실행 중" : nil,
                protectedReason: isRunning ? "실행 중" : nil,
                policy: policy
            )
        }
    }

    private func scanBrowserData(policy: ProtectionPolicy) async throws -> [CleanupItem] {
        let library = home.appending(path: "Library")
        let runningBundleIdentifiers = await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
        var candidates: [BrowserCacheCandidate] = []
        for browser in Self.browserRoots {
            try Task.checkCancellation()
            let running = runningBundleIdentifiers.contains(browser.bundleIdentifier)
            for cachePath in browser.cachePaths {
                let cache = library.appending(path: cachePath)
                if fileManager.fileExists(atPath: cache.path) {
                    candidates.append(
                        BrowserCacheCandidate(
                            url: cache,
                            browserName: browser.name,
                            running: running
                        ))
                }
            }
            for supportPath in browser.supportPaths {
                let supportRoot = library.appending(path: supportPath)
                guard await directoryAccess.canEnumerate(supportRoot) else { continue }
                let urls = try browserSupportCacheURLs(root: supportRoot)
                candidates.append(
                    contentsOf: urls.map {
                        BrowserCacheCandidate(url: $0, browserName: browser.name, running: running)
                    })
            }
        }

        let sizes = try await diskUsage.sizes(of: candidates.map(\.url))
        let items = candidates.compactMap { candidate -> CleanupItem? in
            guard let size = sizes[candidate.url.standardizedFileURL.path],
                size >= minimumCandidateSize
            else { return nil }
            return try? makeFileItem(
                url: candidate.url,
                category: .browserData,
                kind: .browserCache,
                measuredSize: size,
                risk: candidate.running ? .protected : .safe,
                recommendation: candidate.running ? .avoid : .recommended,
                source: candidate.browserName,
                detail: candidate.running ? "브라우저 실행 중" : nil,
                protectedReason: candidate.running ? "실행 중" : nil,
                policy: policy
            )
        }
        return deduplicated(items)
    }

    private func browserSupportCacheURLs(root: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: root.path),
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            )
        else {
            return []
        }

        let names = Set([
            "Cache",
            "cache2",
            "Code Cache",
            "GPUCache",
            "CacheStorage",
            "ShaderCache",
            "GrShaderCache",
            "DawnCache",
            "startupCache",
        ])
        var urls: [URL] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let depth = url.pathComponents.count - root.pathComponents.count
            if depth > 6 {
                enumerator.skipDescendants()
                continue
            }
            guard names.contains(url.lastPathComponent),
                (try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]))?.isDirectory == true
            else {
                continue
            }
            urls.append(url)
            enumerator.skipDescendants()
        }
        return urls
    }

    private func scanDeveloperData(policy: ProtectionPolicy) async throws -> [CleanupItem] {
        struct Candidate {
            let title: String
            let path: String
            let risk: CleanupRisk
            let recommendation: CleanupRecommendation
        }

        let candidates = [
            Candidate(
                title: "Xcode DerivedData", path: "Library/Developer/Xcode/DerivedData", risk: .safe,
                recommendation: .recommended),
            Candidate(
                title: "Xcode Archives", path: "Library/Developer/Xcode/Archives", risk: .sensitive,
                recommendation: .avoid),
            Candidate(
                title: "Xcode DeviceSupport", path: "Library/Developer/Xcode/iOS DeviceSupport", risk: .review,
                recommendation: .optional),
            Candidate(
                title: "Simulator Caches", path: "Library/Developer/CoreSimulator/Caches", risk: .safe,
                recommendation: .recommended),
            Candidate(title: "npm Cache", path: ".npm/_cacache", risk: .safe, recommendation: .recommended),
            Candidate(title: "pnpm Store", path: "Library/pnpm/store", risk: .review, recommendation: .optional),
            Candidate(title: "uv Cache", path: ".cache/uv", risk: .safe, recommendation: .recommended),
            Candidate(title: "Gradle Cache", path: ".gradle/caches", risk: .safe, recommendation: .recommended),
            Candidate(title: "Cargo Cache", path: ".cargo/registry/cache", risk: .safe, recommendation: .recommended),
            Candidate(
                title: "Homebrew Cache", path: "Library/Caches/Homebrew", risk: .safe, recommendation: .recommended),
            Candidate(title: "Codex Runtimes", path: ".cache/codex-runtimes", risk: .review, recommendation: .optional),
        ]

        let existing = candidates.compactMap { candidate -> (Candidate, URL)? in
            let url = home.appending(path: candidate.path)
            return fileManager.fileExists(atPath: url.path) ? (candidate, url) : nil
        }
        let sizes = try await diskUsage.sizes(of: existing.map(\.1))
        return existing.compactMap { candidate, url in
            guard let size = sizes[url.standardizedFileURL.path],
                size >= minimumCandidateSize
            else { return nil }
            return try? makeFileItem(
                url: url,
                category: .developerData,
                kind: .developerCache,
                displayName: candidate.title,
                measuredSize: size,
                risk: candidate.risk,
                recommendation: candidate.recommendation,
                source: "개발 도구",
                policy: policy
            )
        }
    }

    private func scanLogs(policy: ProtectionPolicy) async throws -> [CleanupItem] {
        let root = home.appending(path: "Library/Logs")
        let candidates = try topLevelItems(at: root, includeHidden: false).map { url in
            (
                url: url,
                source: url.lastPathComponent == "DiagnosticReports"
                    ? "진단 보고서"
                    : "로그"
            )
        }
        let sizes = try await diskUsage.sizes(of: candidates.map(\.url))
        let items = candidates.compactMap { candidate -> CleanupItem? in
            guard let size = sizes[candidate.url.standardizedFileURL.path],
                size >= minimumCandidateSize
            else { return nil }
            return try? makeFileItem(
                url: candidate.url,
                category: .logs,
                kind: .log,
                measuredSize: size,
                risk: .safe,
                recommendation: .recommended,
                source: candidate.source,
                policy: policy
            )
        }
        return deduplicated(items)
    }

    private func scanTrash(policy: ProtectionPolicy) async throws -> [CleanupItem] {
        let root = home.appending(path: ".Trash")
        guard await directoryAccess.canEnumerate(root) else {
            throw TrashAccessError.permissionDenied
        }
        do {
            let urls = try topLevelItems(at: root, includeHidden: true)
            let sizes = try await diskUsage.sizes(of: urls)
            return urls.compactMap { url in
                guard let size = sizes[url.standardizedFileURL.path] else { return nil }
                return try? makeFileItem(
                    url: url,
                    category: .trash,
                    kind: .trash,
                    measuredSize: size,
                    risk: .review,
                    recommendation: .optional,
                    operation: .removeImmediately,
                    source: "휴지통",
                    policy: policy
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Self.isPermissionDenied(error) {
                throw TrashAccessError.permissionDenied
            }
            throw TrashAccessError.unavailable(error.localizedDescription)
        }
    }

    private static func isPermissionDenied(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
            nsError.code == CocoaError.Code.fileReadNoPermission.rawValue
        {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
            [Int(EACCES), Int(EPERM)].contains(nsError.code)
        {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? any Error {
            return isPermissionDenied(underlying)
        }
        return false
    }

    private func scanCustom(
        preferences: CleanupPreferences,
        policy: ProtectionPolicy
    ) async throws -> [CleanupItem] {
        var candidates: [(url: URL, source: String)] = []
        for root in preferences.customScanRoots {
            for url in try topLevelItems(at: root, includeHidden: preferences.includeHiddenFiles) {
                candidates.append((url, root.lastPathComponent))
            }
        }
        let sizes = try await diskUsage.sizes(of: candidates.map(\.url))
        var items: [CleanupItem] = []
        for candidate in candidates {
            try Task.checkCancellation()
            let measuredSize = sizes[candidate.url.standardizedFileURL.path] ?? 0
            let size =
                measuredSize > 0
                ? measuredSize
                : try allocatedSize(of: candidate.url)
            if let item = try? makeFileItem(
                url: candidate.url,
                category: .custom,
                kind: .custom,
                measuredSize: size,
                risk: .review,
                recommendation: .optional,
                source: candidate.source,
                policy: policy
            ) {
                items.append(item)
            }
        }
        return deduplicated(items)
    }

    private var defaultFileRoots: [URL] {
        ["Documents", "Downloads", "Desktop", "Movies", "Music", "Pictures"]
            .map { home.appending(path: $0) }
    }

    private func topLevelItems(at root: URL, includeHidden: Bool) throws -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        return try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options.contains(.skipsHiddenFiles) ? [.skipsHiddenFiles] : []
        )
        .filter { url in
            (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true
        }
    }

    private func genericCacheCandidates(at root: URL) throws -> [URL] {
        let library = home.appending(path: "Library")
        let dedicatedPaths = Set(
            Self.browserRoots
                .flatMap(\.cachePaths)
                .map { library.appending(path: $0).standardizedFileURL.path }
                + [library.appending(path: "Caches/Homebrew").standardizedFileURL.path]
        )
        return try topLevelItems(at: root, includeHidden: false).flatMap { url in
            try cacheCandidates(outside: dedicatedPaths, at: url)
        }
    }

    private func cacheCandidates(
        outside dedicatedPaths: Set<String>,
        at url: URL
    ) throws -> [URL] {
        let path = url.standardizedFileURL.path
        if dedicatedPaths.contains(path) { return [] }

        let dedicatedDescendants = dedicatedPaths.filter {
            $0.hasPrefix(path + "/")
        }
        guard !dedicatedDescendants.isEmpty else { return [url] }
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            return [url]
        }
        return try topLevelItems(at: url, includeHidden: false).flatMap { child in
            try cacheCandidates(outside: dedicatedPaths, at: child)
        }
    }

    private func makeFileItem(
        url: URL,
        category: CleanupCategory,
        kind: CleanupItemKind,
        displayName: String? = nil,
        measuredSize: Int64? = nil,
        risk: CleanupRisk,
        recommendation: CleanupRecommendation,
        operation: CleanupOperation = .recycle,
        source: String,
        detail: String? = nil,
        protectedReason: String? = nil,
        policy: ProtectionPolicy
    ) throws -> CleanupItem {
        let values = try url.resourceValues(forKeys: resourceKeys)
        guard values.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let decision = policy.decision(for: url)
        let finalReason = protectedReason ?? decision.reason
        let finalRisk: CleanupRisk = finalReason == nil ? risk : .protected
        let finalRecommendation: CleanupRecommendation = finalReason == nil ? recommendation : .avoid
        let size: Int64
        if let measuredSize {
            size = measuredSize
        } else {
            size = try allocatedSize(of: url)
        }
        return CleanupItem(
            id: CleanupItem.stableID(prefix: category.rawValue, value: url.standardizedFileURL.path),
            category: category,
            kind: kind,
            name: displayName ?? url.lastPathComponent,
            url: url,
            size: size,
            modifiedAt: values.contentModificationDate,
            risk: finalRisk,
            recommendation: finalRecommendation,
            operation: operation,
            source: source,
            detail: detail,
            protectedReason: finalReason,
            bundleIdentifier: nil,
            duplicateGroupID: nil,
            metadata: [:]
        )
    }

    private func kind(for url: URL) -> CleanupItemKind {
        let ext = url.pathExtension.lowercased()
        if ["dmg", "pkg", "mpkg", "xip"].contains(ext) {
            return .installer
        }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        return isDirectory ? .folder : .file
    }

    private func deduplicated(_ items: [CleanupItem]) -> [CleanupItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private static let browserRoots: [BrowserRoot] = [
        BrowserRoot(
            name: "Chrome",
            bundleIdentifier: "com.google.Chrome",
            cachePaths: ["Caches/Google/Chrome"],
            supportPaths: ["Application Support/Google/Chrome"]
        ),
        BrowserRoot(
            name: "Brave",
            bundleIdentifier: "com.brave.Browser",
            cachePaths: ["Caches/BraveSoftware/Brave-Browser"],
            supportPaths: ["Application Support/BraveSoftware/Brave-Browser"]
        ),
        BrowserRoot(
            name: "Whale",
            bundleIdentifier: "com.naver.Whale",
            cachePaths: ["Caches/Naver/Whale"],
            supportPaths: ["Application Support/Naver/Whale"]
        ),
        BrowserRoot(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            cachePaths: [
                "Caches/com.apple.Safari",
                "Containers/com.apple.Safari/Data/Library/Caches",
            ],
            supportPaths: []
        ),
        BrowserRoot(
            name: "Firefox",
            bundleIdentifier: "org.mozilla.firefox",
            cachePaths: ["Caches/Firefox/Profiles"],
            supportPaths: []
        ),
        BrowserRoot(
            name: "Edge",
            bundleIdentifier: "com.microsoft.edgemac",
            cachePaths: ["Caches/Microsoft Edge"],
            supportPaths: ["Application Support/Microsoft Edge"]
        ),
        BrowserRoot(
            name: "Arc",
            bundleIdentifier: "company.thebrowser.Browser",
            cachePaths: ["Caches/company.thebrowser.Browser"],
            supportPaths: ["Application Support/Arc/User Data"]
        ),
        BrowserRoot(
            name: "Vivaldi",
            bundleIdentifier: "com.vivaldi.Vivaldi",
            cachePaths: ["Caches/Vivaldi"],
            supportPaths: ["Application Support/Vivaldi"]
        ),
        BrowserRoot(
            name: "Opera",
            bundleIdentifier: "com.operasoftware.Opera",
            cachePaths: ["Caches/com.operasoftware.Opera"],
            supportPaths: ["Application Support/com.operasoftware.Opera"]
        ),
        BrowserRoot(
            name: "Orion",
            bundleIdentifier: "com.kagi.kagimacOS",
            cachePaths: ["Caches/com.kagi.kagimacOS"],
            supportPaths: []
        ),
    ]
}
