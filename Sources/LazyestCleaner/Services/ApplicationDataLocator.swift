import Darwin
import Foundation
import Security

private struct ApplicationDataLocation: Sendable {
    let url: URL
    let relativePath: String
    let risk: CleanupRisk
}

actor ApplicationDataLocator {
    private let fileManager: FileManager
    private let home: URL
    private let fileScanner: FileScanner

    init(
        fileManager: FileManager = .default,
        home: URL? = nil,
        fileScanner: FileScanner
    ) {
        self.fileManager = fileManager
        self.home = home ?? fileManager.homeDirectoryForCurrentUser
        self.fileScanner = fileScanner
    }

    func scanData(
        for applications: [CleanupItem],
        policy: ProtectionPolicy
    ) async throws -> [CleanupItem] {
        var located: [(application: CleanupItem, location: ApplicationDataLocation)] = []
        var seen = Set<String>()

        for application in applications where application.kind == .application {
            try Task.checkCancellation()
            for location in candidateLocations(for: application) {
                let path = location.url.standardizedFileURL.path
                guard fileManager.fileExists(atPath: path) else { continue }
                guard (try? location.url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true else {
                    continue
                }
                guard seen.insert(fileIdentity(for: location.url)).inserted else { continue }
                located.append((application, location))
            }
        }

        let minimized =
            located
            .sorted { $0.location.url.path.count < $1.location.url.path.count }
            .reduce(into: [(application: CleanupItem, location: ApplicationDataLocation)]()) { result, candidate in
                let path = candidate.location.url.standardizedFileURL.path
                guard
                    !result.contains(where: {
                        path.hasPrefix($0.location.url.standardizedFileURL.path + "/")
                    })
                else { return }
                result.append(candidate)
            }

        let sizes = try await fileScanner.batchAllocatedSizes(
            of: minimized.map { $0.location.url }
        )
        var items: [CleanupItem] = []
        for candidate in minimized {
            try Task.checkCancellation()
            let application = candidate.application
            let location = candidate.location
            let decision = policy.decision(
                for: location.url,
                bundleIdentifier: application.bundleIdentifier
            )
            let protectedReason = decision.reason
            let size = sizes[location.url.standardizedFileURL.path] ?? 0
            let modifiedAt = try? location.url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate

            items.append(
                CleanupItem(
                    id: CleanupItem.stableID(prefix: "appData", value: location.url.standardizedFileURL.path),
                    category: .leftovers,
                    kind: .appLeftover,
                    name: location.relativePath,
                    url: location.url,
                    size: size,
                    modifiedAt: modifiedAt,
                    risk: protectedReason == nil ? location.risk : .protected,
                    recommendation: .avoid,
                    operation: .recycle,
                    source: application.name,
                    detail: nil,
                    protectedReason: protectedReason,
                    bundleIdentifier: application.bundleIdentifier,
                    duplicateGroupID: nil,
                    metadata: ["앱": application.name]
                ))
        }
        return items.sorted { $0.size > $1.size }
    }

    private func candidateLocations(for application: CleanupItem) -> [ApplicationDataLocation] {
        let library = home.appending(path: "Library")
        var candidates: [(String, CleanupRisk)] = []

        if let identifier = application.bundleIdentifier,
            isSafePathComponent(identifier)
        {
            candidates += [
                ("Application Support/\(identifier)", .sensitive),
                ("Caches/\(identifier)", .review),
                ("Containers/\(identifier)", .sensitive),
                ("HTTPStorages/\(identifier)", .review),
                ("WebKit/\(identifier)", .sensitive),
                ("Preferences/\(identifier).plist", .sensitive),
                ("Saved Application State/\(identifier).savedState", .review),
                ("Application Scripts/\(identifier)", .sensitive),
                ("Logs/\(identifier)", .review),
                ("Cookies/\(identifier).binarycookies", .sensitive),
                ("SyncedPreferences/\(identifier).plist", .sensitive),
            ]
            candidates += byHostPreferenceLocations(bundleIdentifier: identifier)
        }

        if isSafePathComponent(application.name) {
            candidates += [
                ("Application Support/\(application.name)", .sensitive),
                ("Caches/\(application.name)", .review),
                ("Logs/\(application.name)", .review),
            ]
        }

        candidates += manifestLocations(for: application)
        candidates += namedLocations(for: application)
        candidates += applicationGroupIdentifiers(for: application).map {
            ("Group Containers/\($0)", .sensitive)
        }

        var seen = Set<String>()
        return candidates.compactMap { relativePath, risk in
            let url = library.appending(path: relativePath)
            guard seen.insert(url.standardizedFileURL.path).inserted else { return nil }
            return ApplicationDataLocation(url: url, relativePath: relativePath, risk: risk)
        }
    }

    private func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains(":")
    }

    private func manifestLocations(for application: CleanupItem) -> [(String, CleanupRisk)] {
        guard let identifier = application.bundleIdentifier else { return [] }
        return Self.applicationDataManifests[identifier] ?? []
    }

    private func namedLocations(for application: CleanupItem) -> [(String, CleanupRisk)] {
        let aliases = normalizedAliases(for: application)
        guard !aliases.isEmpty else { return [] }

        let roots: [(relativePath: String, risk: CleanupRisk)] = [
            ("Application Support", .sensitive),
            ("Caches", .review),
            ("Logs", .review),
        ]
        let library = home.appending(path: "Library")
        var matches: [(String, CleanupRisk)] = []

        for root in roots {
            let rootURL = library.appending(path: root.relativePath)
            guard
                let children = try? fileManager.contentsOfDirectory(
                    at: rootURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                )
            else { continue }

            for child in children {
                guard isUsableCandidate(child) else { continue }
                let childRelative = child.lastPathComponent
                let childAlias = normalized(childRelative)
                if aliases.contains(childAlias) {
                    matches.append(("\(root.relativePath)/\(childRelative)", root.risk))
                }

                let canContainNestedMatch = aliases.contains {
                    $0.count > childAlias.count && $0.hasPrefix(childAlias)
                }
                guard canContainNestedMatch,
                    (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                    let grandchildren = try? fileManager.contentsOfDirectory(
                        at: child,
                        includingPropertiesForKeys: [.isSymbolicLinkKey],
                        options: [.skipsHiddenFiles]
                    )
                else { continue }
                for grandchild in grandchildren where isUsableCandidate(grandchild) {
                    let relative = "\(childRelative)/\(grandchild.lastPathComponent)"
                    if aliases.contains(normalized(relative)) {
                        matches.append(("\(root.relativePath)/\(relative)", root.risk))
                    }
                }
            }
        }
        return matches
    }

    private func byHostPreferenceLocations(bundleIdentifier: String) -> [(String, CleanupRisk)] {
        let root = home.appending(path: "Library/Preferences/ByHost")
        guard
            let urls = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }
        return urls.compactMap { url in
            guard isUsableCandidate(url),
                url.lastPathComponent.hasPrefix(bundleIdentifier + "."),
                url.pathExtension.lowercased() == "plist"
            else { return nil }
            return ("Preferences/ByHost/\(url.lastPathComponent)", .sensitive)
        }
    }

    private func applicationGroupIdentifiers(for application: CleanupItem) -> [String] {
        guard let applicationURL = application.url else { return [] }
        var staticCode: SecStaticCode?
        guard
            SecStaticCodeCreateWithPath(
                applicationURL as CFURL,
                SecCSFlags(rawValue: 0),
                &staticCode
            ) == errSecSuccess, let staticCode
        else { return [] }

        var signingInformation: CFDictionary?
        guard
            SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &signingInformation
            ) == errSecSuccess,
            let dictionary = signingInformation as? [String: Any],
            let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
            let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else {
            return []
        }
        return groups.filter(isSafePathComponent)
    }

    private func normalizedAliases(for application: CleanupItem) -> Set<String> {
        var values = [application.name]
        values += [application.metadata["bundleName"], application.metadata["executable"]]
            .compactMap { $0 }

        if let identifier = application.bundleIdentifier {
            values.append(identifier)
            let components = identifier.split(separator: ".").map(String.init)
            if components.count >= 2 {
                values.append(components.suffix(2).joined())
            }
            if components.count >= 3,
                ["com", "org", "net", "io", "company"].contains(components[0].lowercased())
            {
                values.append(components.dropFirst().joined())
            }
            if let last = components.last {
                values.append(last)
            }
        }

        return Set(values.map(normalized).filter { $0.count >= 4 })
    }

    private func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func isUsableCandidate(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true
    }

    private func fileIdentity(for url: URL) -> String {
        var metadata = stat()
        let status = url.path.withCString { path in
            lstat(path, &metadata)
        }
        guard status == 0 else {
            return "path:\(url.standardizedFileURL.path)"
        }
        return "file:\(metadata.st_dev):\(metadata.st_ino)"
    }

    private static let applicationDataManifests: [String: [(String, CleanupRisk)]] = [
        "com.apple.dt.Xcode": [
            ("Developer/Xcode", .sensitive)
        ],
        "com.brave.Browser": [
            ("Application Support/BraveSoftware/Brave-Browser", .sensitive),
            ("Caches/BraveSoftware/Brave-Browser", .review),
        ],
    ]
}
