import Foundation

actor HistoryRepository {
    private let fileURL: URL

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let root =
                fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
            let current = root.appending(path: "Lazyest Cleaner/history.json")
            let legacyCandidates = [
                root.appending(path: "Lazyest Tidy/history.json"),
                root.appending(path: "TidyMac/history.json"),
            ]
            if !fileManager.fileExists(atPath: current.path),
                let legacy = legacyCandidates.first(where: { candidate in
                    fileManager.fileExists(atPath: candidate.path)
                })
            {
                try? fileManager.createDirectory(
                    at: current.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? fileManager.copyItem(at: legacy, to: current)
            }
            self.fileURL = current
        }
    }

    func load() -> [CleanupHistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([CleanupHistoryEntry].self, from: data)) ?? []
    }

    func append(_ entry: CleanupHistoryEntry) throws -> [CleanupHistoryEntry] {
        var entries = load()
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(200))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
        return entries
    }
}
