import Foundation

enum DirectoryAccessError: LocalizedError, Sendable {
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case let .permissionDenied(name): "\(name) 접근 권한 필요"
        }
    }
}

enum FullDiskAccessError: LocalizedError, Sendable {
    case required

    var errorDescription: String? {
        "전체 디스크 접근 권한 필요"
    }
}

protocol DirectoryAccessChecking: Sendable {
    func canEnumerate(_ url: URL) async -> Bool
    func invalidate() async
}

extension DirectoryAccessChecking {
    func invalidate() async {}
}

actor DirectoryAccessService: DirectoryAccessChecking {
    static let probeTimeout: TimeInterval = 0.75
    static let cacheLifetime: TimeInterval = 30

    private struct CacheEntry {
        let canEnumerate: Bool
        let checkedAt: Date
    }

    private let fileManager: FileManager
    private let runner: any ProcessRunning
    private let executable: URL?
    private var cache: [String: CacheEntry] = [:]

    init(
        runner: any ProcessRunning = ProcessRunner(),
        executable: URL? = URL(fileURLWithPath: "/usr/bin/find")
    ) {
        let fileManager = FileManager.default
        self.fileManager = fileManager
        self.runner = runner
        self.executable = executable.flatMap {
            fileManager.isExecutableFile(atPath: $0.path) ? $0 : nil
        }
    }

    func canEnumerate(_ url: URL) async -> Bool {
        let path = url.standardizedFileURL.path
        if let cached = cache[path],
            Date().timeIntervalSince(cached.checkedAt) < Self.cacheLifetime
        {
            return cached.canEnumerate
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            cache[path] = CacheEntry(canEnumerate: false, checkedAt: Date())
            return false
        }

        guard let executable else {
            return true
        }

        let canEnumerate: Bool
        do {
            let result = try await runner.run(
                executable: executable,
                arguments: [path, "-mindepth", "1", "-maxdepth", "1", "-print", "-quit"],
                timeout: Self.probeTimeout
            )
            canEnumerate = result.exitCode == 0
        } catch {
            canEnumerate = false
        }
        cache[path] = CacheEntry(canEnumerate: canEnumerate, checkedAt: Date())
        return canEnumerate
    }

    func invalidate() async {
        cache.removeAll()
    }
}
