import Foundation

enum ProtectionScope: String, Codable, Sendable {
    case exact
    case subtree
    case subtreeAndAncestors
    case exactAndAncestors
}

struct ProtectionRule: Identifiable, Codable, Sendable {
    let id: String
    let url: URL
    let reason: String
    let scope: ProtectionScope
    let isBuiltIn: Bool
}

struct ProtectionDecision: Sendable {
    let isProtected: Bool
    let reason: String?

    static let allowed = ProtectionDecision(isProtected: false, reason: nil)
}

struct ProtectionPolicy: Sendable {
    let rules: [ProtectionRule]
    let protectedBundleIdentifiers: Set<String>

    init(
        customPaths: [URL] = [],
        home: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let home = home ?? fileManager.homeDirectoryForCurrentUser
        let systemRoots = [
            ("system", "/System"),
            ("usr", "/usr"),
            ("bin", "/bin"),
            ("sbin", "/sbin"),
            ("private", "/private"),
        ].map { id, path in
            ProtectionRule(
                id: id,
                url: URL(fileURLWithPath: path),
                reason: "시스템 경로",
                scope: .subtree,
                isBuiltIn: true
            )
        }
        let protectedHomePaths = [
            ("cloud", "Library/CloudStorage", "클라우드 문서"),
            ("docker-vm", "Library/Containers/com.docker.docker", "Docker 전용 정리"),
            ("keychains", "Library/Keychains", "Keychain 데이터"),
            ("mail", "Library/Mail", "Mail 데이터"),
            ("messages", "Library/Messages", "Messages 데이터"),
            ("photos", "Pictures/Photos Library.photoslibrary", "사진 보관함"),
            ("ssh", ".ssh", "SSH 자격증명"),
            ("gnupg", ".gnupg", "GPG 자격증명"),
            ("aws", ".aws", "AWS 자격증명"),
            ("docker-config", ".docker", "Docker 설정"),
            ("kube", ".kube", "Kubernetes 설정"),
            ("gcloud", ".config/gcloud", "Google Cloud 자격증명"),
            ("npmrc", ".npmrc", "npm 자격증명"),
            ("pypirc", ".pypirc", "Python 저장소 자격증명"),
            ("netrc", ".netrc", "네트워크 자격증명"),
            ("git-credentials", ".git-credentials", "Git 자격증명"),
        ].map { id, path, reason in
            ProtectionRule(
                id: id,
                url: home.appending(path: path),
                reason: reason,
                scope: .subtreeAndAncestors,
                isBuiltIn: true
            )
        }
        let builtIns =
            systemRoots + [
                ProtectionRule(
                    id: "home",
                    url: home,
                    reason: "사용자 홈",
                    scope: .exactAndAncestors,
                    isBuiltIn: true
                )
            ] + protectedHomePaths
        let customs = customPaths.map { url in
            ProtectionRule(
                id: "custom:\(Self.normalizedPath(url))",
                url: url,
                reason: "사용자 보호",
                scope: .subtreeAndAncestors,
                isBuiltIn: false
            )
        }
        rules = builtIns + customs
        protectedBundleIdentifiers = [Bundle.main.bundleIdentifier ?? "com.tidymac.cleaner"]
    }

    func decision(for url: URL, bundleIdentifier: String? = nil) -> ProtectionDecision {
        if let bundleIdentifier, protectedBundleIdentifiers.contains(bundleIdentifier) {
            return ProtectionDecision(isProtected: true, reason: "필수 앱")
        }

        let candidate = Self.normalizedPath(url)
        for rule in rules {
            let protectedPath = Self.normalizedPath(rule.url)
            let insideProtected = Self.contains(parent: protectedPath, child: candidate)
            let containsProtected = Self.contains(parent: candidate, child: protectedPath)
            let matches =
                switch rule.scope {
                case .exact:
                    candidate == protectedPath
                case .subtree:
                    insideProtected
                case .subtreeAndAncestors:
                    insideProtected || containsProtected
                case .exactAndAncestors:
                    candidate == protectedPath || containsProtected
                }
            if matches {
                return ProtectionDecision(isProtected: true, reason: rule.reason)
            }
        }
        return .allowed
    }

    func shouldSkipDescendants(of url: URL) -> Bool {
        let candidate = Self.normalizedPath(url)
        return rules.contains { rule in
            let protectedPath = Self.normalizedPath(rule.url)
            switch rule.scope {
            case .exact, .exactAndAncestors:
                return false
            case .subtree, .subtreeAndAncestors:
                return Self.contains(parent: protectedPath, child: candidate)
            }
        }
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func contains(parent: String, child: String) -> Bool {
        child == parent || child.hasPrefix(parent.hasSuffix("/") ? parent : "\(parent)/")
    }
}
