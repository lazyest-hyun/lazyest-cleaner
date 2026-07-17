import AppKit
import Foundation

private struct OrphanRootDefinition: Sendable {
    let relativePath: String
    let source: String
    let risk: CleanupRisk
    let recommendation: CleanupRecommendation
    let minimumSize: Int64
}

private struct VendorChildPattern: Sendable {
    let root: String
    let prefixes: [String]
}

private struct VendorFootprintDefinition: Sendable {
    let name: String
    let installedBundlePrefixes: [String]
    let exactPaths: [String]
    let childPatterns: [VendorChildPattern]
}

enum ApplicationRootKind: Sendable {
    case installed
    case system
}

struct ApplicationSearchRoot: Sendable {
    let url: URL
    let source: String
    let kind: ApplicationRootKind

    init(url: URL, source: String, kind: ApplicationRootKind = .installed) {
        self.url = url
        self.source = source
        self.kind = kind
    }
}

private struct ApplicationScanCandidate {
    let url: URL
    let path: String
    let name: String
    let source: String
    let modifiedAt: Date?
    let protectedReason: String?
    let running: Bool
    let bundleIdentifier: String?
    let metadata: [String: String]
}

actor ApplicationScanner {
    private let fileManager: FileManager
    private let home: URL
    private let fileScanner: FileScanner
    private let applicationSizer: any ApplicationSizing
    private let applicationRoots: [ApplicationSearchRoot]

    init(
        fileManager: FileManager = .default,
        home: URL? = nil,
        fileScanner: FileScanner,
        applicationSizer: (any ApplicationSizing)? = nil,
        applicationRoots: [ApplicationSearchRoot]? = nil
    ) {
        self.fileManager = fileManager
        let resolvedHome = home ?? fileManager.homeDirectoryForCurrentUser
        self.home = resolvedHome
        self.fileScanner = fileScanner
        self.applicationSizer =
            applicationSizer
            ?? ApplicationSizeService(
                home: resolvedHome,
                fileScanner: fileScanner
            )
        self.applicationRoots =
            applicationRoots ?? [
                ApplicationSearchRoot(url: URL(fileURLWithPath: "/Applications"), source: "응용 프로그램"),
                ApplicationSearchRoot(url: resolvedHome.appending(path: "Applications"), source: "사용자 앱"),
                ApplicationSearchRoot(
                    url: URL(fileURLWithPath: "/System/Applications"), source: "시스템 앱", kind: .system),
                ApplicationSearchRoot(
                    url: URL(fileURLWithPath: "/System/Library/CoreServices/Applications"), source: "시스템 도구",
                    kind: .system),
            ]
    }

    func scanApplications(system: Bool = false, policy: ProtectionPolicy) async throws -> [CleanupItem] {
        let runningBundleIdentifiers = await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
        let roots = system ? applicationRoots : applicationRoots.filter { $0.kind == .installed }
        var candidates: [ApplicationScanCandidate] = []
        var seen = Set<String>()
        for root in roots where fileManager.fileExists(atPath: root.url.path) {
            for url in try applicationURLs(in: root.url) {
                try Task.checkCancellation()
                let canonicalPath = url.standardizedFileURL.resolvingSymlinksInPath().path
                let values = try? url.resourceValues(forKeys: [
                    .contentModificationDateKey,
                    .isSystemImmutableKey,
                ])
                let isSystemApplication =
                    root.kind == .system
                    || canonicalPath == "/System"
                    || canonicalPath.hasPrefix("/System/")
                    || values?.isSystemImmutable == true
                guard isSystemApplication == system else { continue }
                guard seen.insert(canonicalPath).inserted else { continue }
                let bundle = Bundle(url: url)
                let bundleIdentifier = bundle?.bundleIdentifier
                let running = bundleIdentifier.map(runningBundleIdentifiers.contains) ?? false
                let policyDecision = policy.decision(for: url, bundleIdentifier: bundleIdentifier)
                let protectedReason = system ? "시스템 앱" : (running ? "실행 중" : policyDecision.reason)
                let name =
                    bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                let executableName = bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
                let modifiedAt = values?.contentModificationDate
                var metadata: [String: String] = [:]
                metadata["버전"] = version
                metadata["bundleName"] = bundleName
                metadata["executable"] = executableName
                candidates.append(
                    ApplicationScanCandidate(
                        url: url,
                        path: url.standardizedFileURL.path,
                        name: name,
                        source: root.source,
                        modifiedAt: modifiedAt,
                        protectedReason: protectedReason,
                        running: running,
                        bundleIdentifier: bundleIdentifier,
                        metadata: metadata
                    ))
            }
        }

        let sizes = try await applicationSizer.sizes(
            for: candidates.map {
                ApplicationSizeRequest(url: $0.url, modifiedAt: $0.modifiedAt)
            })
        let category: CleanupCategory = system ? .systemApplications : .applications
        return candidates.map { candidate in
            CleanupItem(
                id: CleanupItem.stableID(prefix: category.rawValue, value: candidate.path),
                category: category,
                kind: .application,
                name: candidate.name,
                url: candidate.url,
                size: sizes[candidate.path] ?? 0,
                modifiedAt: candidate.modifiedAt,
                risk: candidate.protectedReason == nil ? .review : .protected,
                recommendation: .avoid,
                operation: system ? .revealOnly : .recycle,
                source: candidate.source,
                detail: candidate.running ? "앱 실행 중" : nil,
                protectedReason: candidate.protectedReason,
                bundleIdentifier: candidate.bundleIdentifier,
                duplicateGroupID: nil,
                metadata: candidate.metadata
            )
        }
        .sorted { $0.size > $1.size }
    }

    private func applicationURLs(in root: URL) throws -> [URL] {
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            )
        else {
            return []
        }

        var applications: [URL] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try? url.resourceValues(forKeys: [.isPackageKey, .isSymbolicLinkKey])
            if url.pathExtension.lowercased() == "app" {
                applications.append(url)
                if values?.isSymbolicLink != true {
                    enumerator.skipDescendants()
                }
            } else if values?.isPackage == true {
                enumerator.skipDescendants()
            }
        }
        return applications
    }

    func scanLeftovers(policy: ProtectionPolicy) async throws -> [CleanupItem] {
        let library = home.appending(path: "Library")
        let installed = installedBundleIdentifiers()
        let genericRoots = [
            OrphanRootDefinition(
                relativePath: "Caches", source: "고아 캐시", risk: .review, recommendation: .optional,
                minimumSize: 20_000_000),
            OrphanRootDefinition(
                relativePath: "Containers", source: "고아 컨테이너", risk: .sensitive, recommendation: .avoid,
                minimumSize: 20_000_000),
            OrphanRootDefinition(
                relativePath: "HTTPStorages", source: "고아 웹 데이터", risk: .review, recommendation: .optional,
                minimumSize: 10_000_000),
            OrphanRootDefinition(
                relativePath: "WebKit", source: "고아 웹 데이터", risk: .sensitive, recommendation: .avoid,
                minimumSize: 10_000_000),
            OrphanRootDefinition(
                relativePath: "Saved Application State", source: "저장 상태", risk: .review, recommendation: .optional,
                minimumSize: 1_000_000),
            OrphanRootDefinition(
                relativePath: "Application Scripts", source: "앱 스크립트", risk: .sensitive, recommendation: .avoid,
                minimumSize: 1_000_000),
            OrphanRootDefinition(
                relativePath: "Application Support", source: "고아 앱 데이터", risk: .sensitive, recommendation: .avoid,
                minimumSize: 20_000_000),
        ]
        var candidates:
            [URL: (
                source: String,
                risk: CleanupRisk,
                recommendation: CleanupRecommendation,
                minimumSize: Int64,
                bundleIdentifier: String?
            )] = [:]

        for definition in genericRoots {
            let root = library.appending(path: definition.relativePath)
            let urls = try genericOrphanCandidates(
                root: root,
                installedBundleIdentifiers: installed
            )
            for url in urls {
                candidates[url] = (
                    definition.source,
                    definition.risk,
                    definition.recommendation,
                    definition.minimumSize,
                    inferredBundleIdentifier(from: url.lastPathComponent)
                )
            }
        }

        for vendor in Self.vendorFootprints where !vendor.hasInstalledApplication(in: installed) {
            for relativePath in vendor.exactPaths {
                let url = library.appending(path: relativePath)
                if fileManager.fileExists(atPath: url.path) {
                    let info = Self.candidateInfo(source: vendor.name, url: url)
                    candidates[url] = (
                        info.source, info.risk, info.recommendation, 1_000_000, nil
                    )
                }
            }
            for pattern in vendor.childPatterns {
                let root = library.appending(path: pattern.root)
                guard fileManager.fileExists(atPath: root.path) else { continue }
                let children = try fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                for url in children
                where pattern.prefixes.contains(where: { prefix in
                    url.lastPathComponent.localizedCaseInsensitiveHasPrefix(prefix)
                }) {
                    let info = Self.candidateInfo(source: vendor.name, url: url)
                    candidates[url] = (
                        info.source, info.risk, info.recommendation, 1_000_000, nil
                    )
                }
            }
        }

        let sizes = try await fileScanner.batchAllocatedSizes(of: Array(candidates.keys))
        var items: [CleanupItem] = []
        for (url, info) in candidates.sorted(by: { $0.key.path < $1.key.path }) {
            try Task.checkCancellation()
            let size = sizes[url.standardizedFileURL.path] ?? 0
            guard size >= info.minimumSize else { continue }
            if let bundleIdentifier = info.bundleIdentifier,
                await applicationURL(bundleIdentifier: bundleIdentifier) != nil
            {
                continue
            }
            let decision = policy.decision(for: url)
            items.append(
                CleanupItem(
                    id: CleanupItem.stableID(
                        prefix: CleanupCategory.leftovers.rawValue, value: url.standardizedFileURL.path),
                    category: .leftovers,
                    kind: .appLeftover,
                    name: url.lastPathComponent,
                    url: url,
                    size: size,
                    modifiedAt: try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                    risk: decision.isProtected ? .protected : info.risk,
                    recommendation: decision.isProtected ? .avoid : info.recommendation,
                    operation: .recycle,
                    source: info.source,
                    detail: nil,
                    protectedReason: decision.reason,
                    bundleIdentifier: info.bundleIdentifier,
                    duplicateGroupID: nil,
                    metadata: [:]
                ))
        }
        return items.sorted { $0.size > $1.size }
    }

    private func genericOrphanCandidates(
        root: URL,
        installedBundleIdentifiers: Set<String>
    ) throws -> Set<URL> {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let children = try fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var result = Set<URL>()
        for url in children {
            try Task.checkCancellation()
            guard let bundleIdentifier = inferredBundleIdentifier(from: url.lastPathComponent),
                !installedBundleIdentifiers.contains(bundleIdentifier)
            else {
                continue
            }
            result.insert(url)
        }
        return result
    }

    private func inferredBundleIdentifier(from name: String) -> String? {
        let normalized =
            name
            .replacingOccurrences(of: ".savedState", with: "")
            .replacingOccurrences(of: ".plist", with: "")
        let prefixes = ["com.", "org.", "net.", "io."]
        guard prefixes.contains(where: normalized.hasPrefix), !normalized.contains(" ") else { return nil }
        return normalized
    }

    private func applicationURL(bundleIdentifier: String) async -> URL? {
        await MainActor.run {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }
    }

    private func installedBundleIdentifiers() -> Set<String> {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            home.appending(path: "Applications"),
        ]
        var identifiers = Set<String>()
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard
                let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                    options: [.skipsHiddenFiles],
                    errorHandler: { _, _ in true }
                )
            else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                if let identifier = Bundle(url: url)?.bundleIdentifier {
                    identifiers.insert(identifier)
                }
                enumerator.skipDescendants()
            }
        }
        return identifiers
    }

    private static func candidateInfo(
        source: String,
        url: URL
    ) -> (source: String, risk: CleanupRisk, recommendation: CleanupRecommendation) {
        let isCache = url.path.contains("/Library/Caches/")
        return (source, isCache ? .review : .sensitive, isCache ? .optional : .avoid)
    }

    private static let vendorFootprints: [VendorFootprintDefinition] = [
        VendorFootprintDefinition(
            name: "Microsoft",
            installedBundlePrefixes: ["com.microsoft."],
            exactPaths: ["Application Support/Microsoft"],
            childPatterns: [
                VendorChildPattern(root: "Caches", prefixes: ["com.microsoft.", "Microsoft"]),
                VendorChildPattern(root: "Containers", prefixes: ["com.microsoft."]),
                VendorChildPattern(root: "Group Containers", prefixes: ["UBF8T346G9."]),
            ]
        ),
        VendorFootprintDefinition(
            name: "Adobe",
            installedBundlePrefixes: ["com.adobe."],
            exactPaths: ["Application Support/Adobe"],
            childPatterns: [
                VendorChildPattern(root: "Caches", prefixes: ["Adobe", "com.adobe."])
            ]
        ),
        VendorFootprintDefinition(
            name: "JetBrains",
            installedBundlePrefixes: ["com.jetbrains."],
            exactPaths: ["Application Support/JetBrains", "Caches/JetBrains"],
            childPatterns: []
        ),
    ]
}

private extension VendorFootprintDefinition {
    func hasInstalledApplication(in bundleIdentifiers: Set<String>) -> Bool {
        bundleIdentifiers.contains { identifier in
            installedBundlePrefixes.contains { identifier.hasPrefix($0) }
        }
    }
}

private extension String {
    func localizedCaseInsensitiveHasPrefix(_ prefix: String) -> Bool {
        range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
    }
}
