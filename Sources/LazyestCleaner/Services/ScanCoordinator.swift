import Foundation

actor ScanCoordinator {
    private let directoryAccess: any DirectoryAccessChecking
    private let fullDiskAccessProbeURL: URL
    private let fileInventory: FileInventoryService
    private let fileScanner: FileScanner
    private let applicationScanner: ApplicationScanner
    private let applicationDataLocator: ApplicationDataLocator
    private let duplicateScanner: DuplicateScanner
    private let dockerService: DockerService
    private let storageService: StorageSnapshotService
    private var fullDiskAccessGranted = false

    init(
        fileScanner: FileScanner? = nil,
        duplicateScanner: DuplicateScanner? = nil,
        dockerService: DockerService = DockerService(),
        storageService: StorageSnapshotService = StorageSnapshotService(),
        directoryAccess: (any DirectoryAccessChecking)? = nil,
        fullDiskAccessProbeURL: URL? = nil
    ) {
        let resolvedDirectoryAccess = directoryAccess ?? DirectoryAccessService()
        let inventory = FileInventoryService(directoryAccess: resolvedDirectoryAccess)
        let resolvedFileScanner =
            fileScanner
            ?? FileScanner(
                fileInventory: inventory,
                directoryAccess: resolvedDirectoryAccess
            )
        self.directoryAccess = resolvedDirectoryAccess
        self.fullDiskAccessProbeURL =
            fullDiskAccessProbeURL
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
        self.fileInventory = inventory
        self.fileScanner = resolvedFileScanner
        self.applicationScanner = ApplicationScanner(fileScanner: resolvedFileScanner)
        self.applicationDataLocator = ApplicationDataLocator(fileScanner: resolvedFileScanner)
        self.duplicateScanner = duplicateScanner ?? DuplicateScanner(fileInventory: inventory)
        self.dockerService = dockerService
        self.storageService = storageService
    }

    func beginScan() async -> Bool {
        await fileInventory.invalidate()
        if !fullDiskAccessGranted {
            fullDiskAccessGranted = await directoryAccess.canEnumerate(fullDiskAccessProbeURL)
        }
        return fullDiskAccessGranted
    }

    func refreshFullDiskAccess() async -> Bool {
        await directoryAccess.invalidate()
        fullDiskAccessGranted = await directoryAccess.canEnumerate(fullDiskAccessProbeURL)
        return fullDiskAccessGranted
    }

    func scan(
        category: CleanupCategory,
        preferences: CleanupPreferences,
        policy: ProtectionPolicy
    ) async throws -> [CleanupItem] {
        if category.requiresFullDiskAccess, !fullDiskAccessGranted {
            throw FullDiskAccessError.required
        }

        let items: [CleanupItem]
        switch category {
        case .overview, .history, .settings:
            items = []
        case .quickClean:
            async let caches = fileScanner.scan(category: .caches, preferences: preferences, policy: policy)
            async let browsers = fileScanner.scan(category: .browserData, preferences: preferences, policy: policy)
            async let developer = fileScanner.scan(category: .developerData, preferences: preferences, policy: policy)
            async let logs = fileScanner.scan(category: .logs, preferences: preferences, policy: policy)
            let (cacheItems, browserItems, developerItems, logItems) = try await (
                caches,
                browsers,
                developer,
                logs
            )
            items = Self.makeQuickCleanItems(
                from: cacheItems + browserItems + developerItems + logItems
            )
        case .applications:
            items = try await applicationScanner.scanApplications(system: false, policy: policy)
        case .systemApplications:
            items = try await applicationScanner.scanApplications(system: true, policy: policy)
        case .leftovers:
            items = try await applicationScanner.scanLeftovers(policy: policy)
        case .duplicates:
            items = try await duplicateScanner.scan(preferences: preferences, policy: policy)
        case .docker:
            items = try await dockerService.scan(preferences: preferences)
        default:
            items = try await fileScanner.scan(category: category, preferences: preferences, policy: policy)
        }
        return items.sorted {
            if $0.risk != $1.risk { return $0.risk < $1.risk }
            return $0.size > $1.size
        }
    }

    func storageSnapshot() async throws -> StorageSnapshot {
        try await storageService.snapshot()
    }

    func applicationDataItems(
        for applications: [CleanupItem],
        policy: ProtectionPolicy
    ) async throws -> [CleanupItem] {
        try await applicationDataLocator.scanData(for: applications, policy: policy)
    }

    nonisolated static func makeQuickCleanItems(from items: [CleanupItem]) -> [CleanupItem] {
        items
            .filter { $0.recommendation == .recommended && !$0.isProtected }
            .map { item in
                CleanupItem(
                    id: "quick:\(item.id)",
                    category: .quickClean,
                    kind: item.kind,
                    name: item.name,
                    url: item.url,
                    size: item.size,
                    modifiedAt: item.modifiedAt,
                    risk: item.risk,
                    recommendation: item.recommendation,
                    operation: item.operation,
                    source: item.source,
                    detail: item.detail,
                    protectedReason: item.protectedReason,
                    bundleIdentifier: item.bundleIdentifier,
                    duplicateGroupID: item.duplicateGroupID,
                    metadata: item.metadata
                )
            }
    }
}
