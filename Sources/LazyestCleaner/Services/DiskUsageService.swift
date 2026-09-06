import Foundation

enum DiskUsageOutputParser {
    static func parse(_ output: String) -> [String: Int64] {
        var sizes: [String: Int64] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let separator = line.firstIndex(where: { $0 == "\t" || $0 == " " }) else {
                continue
            }

            let countText = line[..<separator].trimmingCharacters(in: .whitespaces)
            let pathText = line[separator...].trimmingCharacters(in: .whitespaces)
            guard let kibibytes = Int64(countText), !pathText.isEmpty else { continue }

            let (bytes, overflow) = kibibytes.multipliedReportingOverflow(by: 1_024)
            guard !overflow else { continue }
            let path = URL(fileURLWithPath: pathText).standardizedFileURL.path
            sizes[path] = bytes
        }

        return sizes
    }
}

protocol DiskUsageMeasuring: Sendable {
    func sizes(of urls: [URL]) async throws -> [String: Int64]
}

actor DiskUsageService: DiskUsageMeasuring {
    static let cacheLifetime: TimeInterval = 5 * 60
    static let batchTimeout: TimeInterval = 1.5
    static let individualTimeout: TimeInterval = 0.75
    static let batchSize = 12
    static let maximumIndividualRetries = 32
    static let maximumBackgroundRefreshPaths = 48

    private struct CacheFile: Codable {
        let version: Int
        var entries: [String: CacheEntry]
    }

    private struct CacheEntry: Codable, Sendable {
        let size: Int64
        let checkedAt: Date
    }

    private struct BatchResult: Sendable {
        let sizes: [String: Int64]
    }

    private let fileManager: FileManager
    private let runner: any ProcessRunning
    private let executable: URL?
    private let cacheURL: URL

    private var didLoadCache = false
    private var cache: [String: CacheEntry] = [:]
    private var refreshingPaths: Set<String> = []

    init(
        fileManager: FileManager = .default,
        home: URL? = nil,
        runner: any ProcessRunning = ProcessRunner(),
        executable: URL? = URL(fileURLWithPath: "/usr/bin/du"),
        cacheURL: URL? = nil
    ) {
        let resolvedHome = home ?? fileManager.homeDirectoryForCurrentUser
        self.fileManager = fileManager
        self.runner = runner
        self.executable = executable.flatMap {
            fileManager.isExecutableFile(atPath: $0.path) ? $0 : nil
        }
        self.cacheURL =
            cacheURL
            ?? resolvedHome
            .appending(path: "Library/Caches/com.lazyest.cleaner")
            .appending(path: "directory-sizes-v1.json")
    }

    func sizes(of urls: [URL]) async throws -> [String: Int64] {
        try Task.checkCancellation()
        loadCacheIfNeeded()

        var seen = Set<String>()
        let uniqueURLs = urls.filter {
            seen.insert($0.standardizedFileURL.path).inserted
        }
        let freshCutoff = Date().addingTimeInterval(-Self.cacheLifetime)
        var result: [String: Int64] = [:]
        var misses: [URL] = []
        var stale: [URL] = []

        for url in uniqueURLs {
            let path = url.standardizedFileURL.path
            if let entry = cache[path] {
                result[path] = entry.size
                if entry.checkedAt < freshCutoff {
                    stale.append(url)
                }
            } else {
                misses.append(url)
            }
        }

        guard let executable else { return result }
        let runner = self.runner

        if !misses.isEmpty {
            let batchSizes = await Self.measureBatches(
                misses,
                executable: executable,
                runner: runner,
                timeout: Self.batchTimeout
            )
            result.merge(batchSizes) { _, new in new }

            try Task.checkCancellation()
            let unresolved = misses.filter {
                batchSizes[$0.standardizedFileURL.path] == nil
            }
            let individualSizes = await measureIndividually(
                unresolved,
                executable: executable,
                runner: runner
            )
            result.merge(individualSizes) { _, new in new }

            let now = Date()
            var didChangeCache = false
            for url in misses {
                let path = url.standardizedFileURL.path
                let size = result[path] ?? 0
                cache[path] = CacheEntry(size: size, checkedAt: now)
                didChangeCache = true
            }
            if didChangeCache {
                trimCache()
                persistCache()
            }
        }

        if !stale.isEmpty {
            scheduleRefresh(
                stale,
                executable: executable,
                runner: runner
            )
        }
        return result
    }

    private func measureIndividually(
        _ urls: [URL],
        executable: URL,
        runner: any ProcessRunning
    ) async -> [String: Int64] {
        let candidates = Array(urls.prefix(Self.maximumIndividualRetries))
        guard !candidates.isEmpty else { return [:] }

        return await withTaskGroup(of: BatchResult.self) { group in
            for url in candidates {
                group.addTask {
                    await Self.measure(
                        [url],
                        executable: executable,
                        runner: runner,
                        timeout: Self.individualTimeout
                    )
                }
            }

            var result: [String: Int64] = [:]
            for await measured in group {
                result.merge(measured.sizes) { _, new in new }
            }
            return result
        }
    }

    private nonisolated static func measureBatches(
        _ urls: [URL],
        executable: URL,
        runner: any ProcessRunning,
        timeout: TimeInterval
    ) async -> [String: Int64] {
        let batches = urls.chunked(size: Self.batchSize)
        return await withTaskGroup(of: BatchResult.self) { group in
            for batch in batches {
                group.addTask {
                    await Self.measure(
                        batch,
                        executable: executable,
                        runner: runner,
                        timeout: timeout
                    )
                }
            }

            var result: [String: Int64] = [:]
            for await measured in group {
                result.merge(measured.sizes) { _, new in new }
            }
            return result
        }
    }

    private nonisolated static func measure(
        _ urls: [URL],
        executable: URL,
        runner: any ProcessRunning,
        timeout: TimeInterval
    ) async -> BatchResult {
        guard !urls.isEmpty else { return BatchResult(sizes: [:]) }
        do {
            let process = try await runner.run(
                executable: executable,
                arguments: ["-sk"] + urls.map { $0.standardizedFileURL.path },
                timeout: timeout
            )
            return BatchResult(sizes: DiskUsageOutputParser.parse(process.stdout))
        } catch {
            return BatchResult(sizes: [:])
        }
    }

    private func scheduleRefresh(
        _ urls: [URL],
        executable: URL,
        runner: any ProcessRunning
    ) {
        let candidates =
            urls
            .filter { !refreshingPaths.contains($0.standardizedFileURL.path) }
            .prefix(Self.maximumBackgroundRefreshPaths)
        let selected = Array(candidates)
        guard !selected.isEmpty else { return }

        let paths = selected.map { $0.standardizedFileURL.path }
        refreshingPaths.formUnion(paths)
        Task.detached(priority: .background) { [weak self] in
            let sizes = await Self.measureBatches(
                selected,
                executable: executable,
                runner: runner,
                timeout: Self.batchTimeout
            )
            await self?.finishRefresh(paths: paths, sizes: sizes)
        }
    }

    private func finishRefresh(paths: [String], sizes: [String: Int64]) {
        for path in paths {
            refreshingPaths.remove(path)
        }
        let now = Date()
        for path in paths {
            let size = sizes[path] ?? cache[path]?.size ?? 0
            cache[path] = CacheEntry(size: size, checkedAt: now)
        }
        trimCache()
        persistCache()
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
        let limit = 2_000
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
            // A failed cache write must not turn a scan into an error.
        }
    }
}

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
