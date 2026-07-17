import Foundation

struct ApplicationSizeRequest: Hashable, Sendable {
    let url: URL
    let modifiedAt: Date?

    var path: String {
        url.standardizedFileURL.path
    }
}

protocol ApplicationSizing: Sendable {
    func sizes(for requests: [ApplicationSizeRequest]) async throws -> [String: Int64]
}

actor ApplicationSizeService: ApplicationSizing {
    static let batchTimeout: TimeInterval = 3
    static let individualTimeout: TimeInterval = 1
    static let batchSize = 12
    static let maximumIndividualRetries = 24
    static let negativeCacheLifetime: TimeInterval = 5 * 60

    private struct CacheFile: Codable {
        let version: Int
        var entries: [String: CacheEntry]
    }

    private struct CacheEntry: Codable {
        let size: Int64
        let modificationTimestamp: TimeInterval
        let checkedAt: Date
    }

    private let fileManager: FileManager
    private let fileScanner: FileScanner
    private let runner: any ProcessRunning
    private let executable: URL?
    private let cacheURL: URL

    private var didLoadCache = false
    private var cache: [String: CacheEntry] = [:]

    init(
        fileManager: FileManager = .default,
        home: URL? = nil,
        fileScanner: FileScanner,
        runner: any ProcessRunning = ProcessRunner(),
        executable: URL? = URL(fileURLWithPath: "/usr/bin/du"),
        cacheURL: URL? = nil
    ) {
        let resolvedHome = home ?? fileManager.homeDirectoryForCurrentUser
        self.fileManager = fileManager
        self.fileScanner = fileScanner
        self.runner = runner
        self.executable = executable.flatMap {
            fileManager.isExecutableFile(atPath: $0.path) ? $0 : nil
        }
        self.cacheURL =
            cacheURL
            ?? resolvedHome
            .appending(path: "Library/Caches/com.tidymac.cleaner")
            .appending(path: "application-sizes-v1.json")
    }

    func sizes(for requests: [ApplicationSizeRequest]) async throws -> [String: Int64] {
        try Task.checkCancellation()
        loadCacheIfNeeded()

        var seen = Set<String>()
        let uniqueRequests = requests.filter { seen.insert($0.path).inserted }
        let negativeCutoff = Date().addingTimeInterval(-Self.negativeCacheLifetime)
        var result: [String: Int64] = [:]
        var misses: [ApplicationSizeRequest] = []

        for request in uniqueRequests {
            if let timestamp = request.modifiedAt?.timeIntervalSinceReferenceDate,
                let cached = cache[request.path],
                cached.modificationTimestamp == timestamp,
                cached.size > 0 || cached.checkedAt >= negativeCutoff
            {
                result[request.path] = cached.size
            } else {
                misses.append(request)
            }
        }

        var measured: [String: Int64] = [:]
        if !misses.isEmpty {
            if let executable {
                measured = await Self.measureBatches(
                    misses,
                    executable: executable,
                    runner: runner
                )
                try Task.checkCancellation()

                let unresolved = misses.filter { measured[$0.path] == nil }
                let individual = await Self.measureIndividually(
                    unresolved,
                    executable: executable,
                    runner: runner
                )
                measured.merge(individual) { _, new in new }
            } else {
                measured = try await fileScanner.batchAllocatedSizes(
                    of: misses.map(\.url)
                )
            }
            result.merge(measured) { _, new in new }

            for request in misses where result[request.path] == nil {
                result[request.path] = cache[request.path]?.size ?? 0
            }
        }

        var didChangeCache = false
        let now = Date()
        for request in misses {
            guard let timestamp = request.modifiedAt?.timeIntervalSinceReferenceDate else {
                continue
            }
            if let size = measured[request.path] {
                cache[request.path] = CacheEntry(
                    size: size,
                    modificationTimestamp: timestamp,
                    checkedAt: now
                )
                didChangeCache = true
            } else if cache[request.path] == nil
                || cache[request.path]?.modificationTimestamp == timestamp
            {
                cache[request.path] = CacheEntry(
                    size: 0,
                    modificationTimestamp: timestamp,
                    checkedAt: now
                )
                didChangeCache = true
            }
        }

        if didChangeCache {
            trimCache()
            persistCache()
        }

        return result
    }

    private nonisolated static func measureBatches(
        _ requests: [ApplicationSizeRequest],
        executable: URL,
        runner: any ProcessRunning
    ) async -> [String: Int64] {
        let batches = stride(from: 0, to: requests.count, by: Self.batchSize).map { start in
            Array(requests[start..<min(start + Self.batchSize, requests.count)])
        }
        return await withTaskGroup(of: [String: Int64].self) { group in
            for batch in batches {
                group.addTask {
                    await measure(
                        batch,
                        executable: executable,
                        runner: runner,
                        timeout: Self.batchTimeout
                    )
                }
            }

            var result: [String: Int64] = [:]
            for await sizes in group {
                result.merge(sizes) { _, new in new }
            }
            return result
        }
    }

    private nonisolated static func measureIndividually(
        _ requests: [ApplicationSizeRequest],
        executable: URL,
        runner: any ProcessRunning
    ) async -> [String: Int64] {
        let candidates = Array(requests.prefix(Self.maximumIndividualRetries))
        return await withTaskGroup(of: [String: Int64].self) { group in
            for request in candidates {
                group.addTask {
                    await measure(
                        [request],
                        executable: executable,
                        runner: runner,
                        timeout: Self.individualTimeout
                    )
                }
            }

            var result: [String: Int64] = [:]
            for await sizes in group {
                result.merge(sizes) { _, new in new }
            }
            return result
        }
    }

    private nonisolated static func measure(
        _ requests: [ApplicationSizeRequest],
        executable: URL,
        runner: any ProcessRunning,
        timeout: TimeInterval
    ) async -> [String: Int64] {
        guard !requests.isEmpty else { return [:] }
        do {
            let process = try await runner.run(
                executable: executable,
                arguments: ["-sk"] + requests.map(\.path),
                timeout: timeout
            )
            return DiskUsageOutputParser.parse(process.stdout)
        } catch {
            return [:]
        }
    }

    private func loadCacheIfNeeded() {
        guard !didLoadCache else { return }
        didLoadCache = true
        guard let data = try? Data(contentsOf: cacheURL),
            let decoded = try? JSONDecoder().decode(CacheFile.self, from: data),
            decoded.version == 1
        else { return }
        cache = decoded.entries
    }

    private func trimCache() {
        let limit = 1_000
        guard cache.count > limit else { return }
        let pathsToRemove =
            cache
            .sorted { $0.value.checkedAt < $1.value.checkedAt }
            .prefix(cache.count - limit)
            .map(\.key)
        for path in pathsToRemove {
            cache.removeValue(forKey: path)
        }
    }

    private func persistCache() {
        do {
            try fileManager.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(CacheFile(version: 1, entries: cache))
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Cache persistence must never prevent an application scan.
        }
    }
}
