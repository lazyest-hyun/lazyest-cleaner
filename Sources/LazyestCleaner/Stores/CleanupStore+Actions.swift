import AppKit
import Foundation

extension CleanupStore {
    func setSelection(_ ids: Set<String>) {
        selectedItemIDs = ids.intersection(Set(visibleItems.map(\.id)))
        focusedItemID = selectedItemIDs.count == 1 ? selectedItemIDs.first : nil
    }

    func focus(_ item: CleanupItem) {
        focusedItemID = item.id
    }

    func toggleSelection(_ item: CleanupItem) {
        guard item.isSelectable else {
            focusedItemID = item.id
            return
        }
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
        focusedItemID = item.id
    }

    func resolution(
        for action: CleanupActionID,
        itemIDs: Set<String>? = nil
    ) -> ActionResolution {
        let selected =
            itemIDs.map { ids in
                visibleItems.filter { ids.contains($0.id) }
            } ?? selectedItems
        return CleanupActionResolver.resolve(
            action,
            context: CleanupActionContext(
                selectedItems: selected,
                visibleItems: visibleItems,
                customProtectedPaths: Set(
                    settings.customProtectedPaths.map {
                        $0.standardizedFileURL.path
                    }),
                supportsCurrentScan: selectedCategory.supportsScan,
                allowImmediateRemoval: settings.allowImmediateRemoval,
                isScanning: isScanning,
                isExecuting: isExecuting,
                isPreparingAction: isPreparingAction
            )
        )
    }

    func requestAction(
        _ action: CleanupActionID,
        itemIDs: Set<String>? = nil
    ) {
        let resolution = resolution(for: action, itemIDs: itemIDs)
        guard resolution.isEnabled else { return }
        if let itemIDs {
            setSelection(itemIDs)
        }

        switch action {
        case .scan:
            scan()
        case .scanAll:
            scanAll()
        case .cancelScan:
            cancelScan()
        case .selectRecommended:
            selectedItemIDs = Set(
                visibleItems.filter {
                    $0.isSelectable && $0.recommendation == .recommended
                }.map(\.id))
            focusedItemID = selectedItemIDs.first
        case .selectAll:
            selectedItemIDs = Set(visibleItems.filter(\.isSelectable).map(\.id))
            focusedItemID = selectedItemIDs.first
        case .clearSelection:
            selectedItemIDs.removeAll()
            focusedItemID = nil
        case .reveal:
            reveal(resolution.items.first)
        case .protect:
            resolution.items.compactMap(\.url).forEach(settings.addProtectedPath)
            scan(selectedCategory)
        case .unprotect:
            resolution.items.compactMap(\.url).forEach(settings.removeProtectedPath)
            scan(selectedCategory)
        case .openTrash:
            selectCategory(.trash)
            if !isScanning {
                scan(.trash)
            }
        case .revealTrash:
            NSWorkspace.shared.open(
                FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
            )
        case .openFullDiskAccess:
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
            ) {
                isAwaitingFullDiskAccessReturn = NSWorkspace.shared.open(url)
            }
        case .addLocation:
            addScanLocations()
        case .openSettings:
            selectCategory(.settings)
        case .removeApplicationOnly:
            pendingConfirmation = CleanupConfirmationRequest(
                action: action,
                items: resolution.items
            )
        case .removeAppData, .uninstallApplication:
            prepareApplicationAction(action, applications: resolution.items)
        case .moveToTrash, .removeImmediately, .deletePermanently, .runDockerCleanup:
            pendingConfirmation = CleanupConfirmationRequest(
                action: action,
                items: resolution.items
            )
        }
    }

    func refreshFullDiskAccessAfterReturning() async {
        guard isAwaitingFullDiskAccessReturn, !demoMode else { return }
        let granted = await scanCoordinator.refreshFullDiskAccess()
        hasCheckedFullDiskAccess = true
        hasFullDiskAccess = granted
        guard granted else { return }

        isAwaitingFullDiskAccessReturn = false
        scanIssues = scanIssues.filter { $0.value.kind != .permissionDenied }
        notice = CleanupNotice(kind: .success, message: "접근 권한 확인됨")
        scanAll()
    }

    func confirmPendingAction() {
        guard let request = pendingConfirmation else { return }
        pendingConfirmation = nil
        execute(request)
    }

    func dismissConfirmation() {
        pendingConfirmation = nil
    }

    func addScanLocations() {
        let urls = PanelService.chooseScanRoots()
        guard !urls.isEmpty else { return }
        urls.forEach(settings.addScanRoot)
        selectedCategory = .custom
        scan(.custom)
    }

    func addProtectedLocations() {
        PanelService.chooseProtectedLocations().forEach(settings.addProtectedPath)
        if selectedCategory.supportsScan, scannedCategories.contains(selectedCategory) {
            scan(selectedCategory)
        }
    }

    func removeScanRoot(_ url: URL) {
        settings.removeScanRoot(url)
        if selectedCategory == .custom { scan(.custom) }
    }

    func removeProtectedPath(_ url: URL) {
        settings.removeProtectedPath(url)
        if selectedCategory.supportsScan, scannedCategories.contains(selectedCategory) {
            scan(selectedCategory)
        }
    }

    func openCategoryAndScan(_ category: CleanupCategory) {
        selectCategory(category)
        scan(category)
    }

    func clearNotice() {
        notice = nil
    }
}
