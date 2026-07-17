import Foundation
import Observation

@MainActor
@Observable
final class CleanupStore {
    let settings: AppSettings

    var selectedCategory: CleanupCategory = .overview
    var selectedItemIDs: Set<String> = []
    var focusedItemID: String?
    var searchText = ""
    var scopeFilter: ItemScopeFilter = .all
    var sortOrder: CleanupSortOrder = .sizeDescending
    var isScanning = false
    var isExecuting = false
    var isPreparingAction = false
    var scanningCategory: CleanupCategory?
    var scanCompletedCount = 0
    var scanTotalCount = 0
    var hasCheckedFullDiskAccess = false
    var hasFullDiskAccess = false
    var isAwaitingFullDiskAccessReturn = false
    var storageSnapshot: StorageSnapshot?
    var history: [CleanupHistoryEntry] = []
    var pendingConfirmation: CleanupConfirmationRequest?
    var notice: CleanupNotice?
    var lastReport: CleanupExecutionReport?

    var itemsByCategory: [CleanupCategory: [CleanupItem]] = [:]
    var scannedCategories: Set<CleanupCategory> = []
    var lastScannedAt: [CleanupCategory: Date] = [:]
    var scanIssues: [CleanupCategory: CleanupScanIssue] = [:]

    @ObservationIgnored let scanCoordinator: ScanCoordinator
    @ObservationIgnored let executor: CleanupExecutor
    @ObservationIgnored let historyRepository: HistoryRepository
    @ObservationIgnored let demoMode: Bool
    @ObservationIgnored var scanTask: Task<Void, Never>?
    @ObservationIgnored var activeScanID: UUID?
    @ObservationIgnored var executionTask: Task<Void, Never>?
    @ObservationIgnored var actionPreparationTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false

    init(
        settings: AppSettings = AppSettings(),
        scanCoordinator: ScanCoordinator = ScanCoordinator(),
        executor: CleanupExecutor = CleanupExecutor(),
        historyRepository: HistoryRepository = HistoryRepository(),
        demoMode: Bool? = nil
    ) {
        self.settings = settings
        self.scanCoordinator = scanCoordinator
        self.executor = executor
        self.historyRepository = historyRepository
        self.demoMode =
            demoMode
            ?? ProcessInfo.processInfo.arguments.contains("--demo")
            || UserDefaults.standard.bool(forKey: "LazyestCleanerDemo")
    }

    deinit {
        scanTask?.cancel()
        executionTask?.cancel()
        actionPreparationTask?.cancel()
    }

    var currentItems: [CleanupItem] {
        itemsByCategory[selectedCategory] ?? []
    }

    var selectedWorkspace: CleanupWorkspace {
        CleanupWorkspace.containing(selectedCategory)
    }

    var scanProgress: Double? {
        guard isScanning, scanTotalCount > 0 else { return nil }
        return Double(scanCompletedCount) / Double(scanTotalCount)
    }

    var scanStatusTitle: String? {
        guard isScanning else { return nil }
        if scanTotalCount > 1 {
            let category = scanningCategory?.title ?? "준비"
            return "\(category) · \(scanCompletedCount)/\(scanTotalCount)"
        }
        return scanningCategory.map { "\($0.title) 스캔 중" }
    }

    var needsFullDiskAccess: Bool {
        hasCheckedFullDiskAccess && !hasFullDiskAccess
    }

    var visibleItems: [CleanupItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return
            currentItems
            .filter { item in
                guard !query.isEmpty else { return true }
                let values = [item.name, item.source, item.url?.path, item.detail]
                return values.compactMap { $0 }.contains {
                    $0.localizedCaseInsensitiveContains(query)
                }
            }
            .filter { item in
                switch scopeFilter {
                case .all: true
                case .recommended: item.recommendation == .recommended && !item.isProtected
                case .review: !item.isProtected && item.recommendation != .recommended
                case .protected: item.isProtected
                }
            }
            .sorted(by: sortPredicate)
    }

    var selectedItems: [CleanupItem] {
        visibleItems.filter { selectedItemIDs.contains($0.id) }
    }

    var focusedItem: CleanupItem? {
        if let focusedItemID,
            let item = currentItems.first(where: { $0.id == focusedItemID })
        {
            return item
        }
        return selectedItems.first
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    var protectedCount: Int {
        visibleItems.count(where: \.isProtected)
    }

    var totalCandidateBytes: Int64 {
        let items = ([CleanupCategory.quickClean] + overviewCategories)
            .flatMap { itemsByCategory[$0] ?? [] }
            .filter(\.isSelectable)
        let pathItems =
            items
            .compactMap { item -> (CleanupItem, String)? in
                item.url.map { (item, $0.standardizedFileURL.path) }
            }
            .sorted { $0.1.count < $1.1.count }

        var accountedRoots: [String] = []
        var total = items.filter { $0.url == nil }.reduce(Int64(0)) { $0 + $1.size }
        for (item, path) in pathItems {
            if accountedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                continue
            }
            accountedRoots.append(path)
            total += item.size
        }
        return total
    }

    func summary(for workspace: CleanupWorkspace) -> (
        count: Int,
        bytes: Int64,
        protected: Int
    ) {
        let items = workspace.categories.flatMap { itemsByCategory[$0] ?? [] }
        return (
            items.count,
            items.reduce(0) { $0 + $1.size },
            items.count(where: \.isProtected)
        )
    }

    func hasScanned(_ workspace: CleanupWorkspace) -> Bool {
        workspace.categories.contains { scannedCategories.contains($0) }
    }

    func scanIssue(for category: CleanupCategory) -> CleanupScanIssue? {
        scanIssues[category]
    }

    var overviewCategories: [CleanupCategory] {
        CleanupCategory.allCases.filter {
            ![.overview, .quickClean, .history].contains($0)
                && !(itemsByCategory[$0] ?? []).isEmpty
        }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        history = await historyRepository.load()

        if demoMode {
            hasCheckedFullDiskAccess = true
            hasFullDiskAccess = true
            itemsByCategory = DemoData.items()
            scannedCategories = Set(itemsByCategory.keys)
            let now = Date()
            lastScannedAt = Dictionary(
                uniqueKeysWithValues: scannedCategories.map { ($0, now) }
            )
            storageSnapshot = DemoData.storage
            return
        }

        hasFullDiskAccess = await scanCoordinator.refreshFullDiskAccess()
        hasCheckedFullDiskAccess = true
        await refreshStorage()
        if settings.autoScan {
            scan(.quickClean)
        }
    }

    func selectCategory(_ category: CleanupCategory) {
        guard selectedCategory != category else { return }
        selectedCategory = category
        selectedItemIDs.removeAll()
        focusedItemID = nil
        searchText = ""
        scopeFilter = .all

        guard category.supportsScan,
            !scannedCategories.contains(category),
            !isScanning
        else { return }
        if category == .custom && settings.customScanRoots.isEmpty { return }
        scan(category)
    }

    func selectWorkspace(_ workspace: CleanupWorkspace) {
        if workspace == selectedWorkspace { return }
        selectCategory(workspace.defaultCategory)
    }

    private func sortPredicate(_ lhs: CleanupItem, _ rhs: CleanupItem) -> Bool {
        switch sortOrder {
        case .sizeDescending:
            if lhs.size == rhs.size {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhs.size > rhs.size
        case .dateDescending:
            return (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
        case .nameAscending:
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .riskAscending:
            if lhs.risk == rhs.risk { return lhs.size > rhs.size }
            return lhs.risk < rhs.risk
        }
    }
}
