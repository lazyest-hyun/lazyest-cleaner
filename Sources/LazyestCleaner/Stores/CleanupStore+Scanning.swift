import Foundation

extension CleanupStore {
    func scan(_ category: CleanupCategory? = nil) {
        let target = category ?? selectedCategory
        guard target.supportsScan, !isExecuting, !isPreparingAction else { return }
        if target == .custom && settings.customScanRoots.isEmpty {
            scannedCategories.insert(target)
            itemsByCategory[target] = []
            return
        }

        scanTask?.cancel()
        let scanID = UUID()
        activeScanID = scanID
        selectedItemIDs.removeAll()
        focusedItemID = nil
        isScanning = true
        scanningCategory = target
        scanCompletedCount = 0
        scanTotalCount = 1
        notice = nil
        scanIssues.removeValue(forKey: target)

        let preferences = settings.snapshot
        let policy = ProtectionPolicy(customPaths: preferences.customProtectedPaths)
        scanTask = Task { [weak self] in
            guard let self else { return }
            defer { finishScan(id: scanID) }
            if !demoMode {
                hasFullDiskAccess = await scanCoordinator.beginScan()
                hasCheckedFullDiskAccess = true
                guard activeScanID == scanID, !Task.isCancelled else { return }
            }
            do {
                let items: [CleanupItem]
                if demoMode {
                    try await Task.sleep(for: .milliseconds(220))
                    items = DemoData.items()[target] ?? []
                } else {
                    items = try await scanCoordinator.scan(
                        category: target,
                        preferences: preferences,
                        policy: policy
                    )
                }
                try Task.checkCancellation()
                guard activeScanID == scanID else { return }
                itemsByCategory[target] = items
                scannedCategories.insert(target)
                lastScannedAt[target] = Date()
                scanIssues.removeValue(forKey: target)
                scanCompletedCount = 1
            } catch is CancellationError {
                return
            } catch {
                guard activeScanID == scanID else { return }
                let issue = CleanupScanIssueMapper.issue(category: target, error: error)
                scanIssues[target] = issue
                scannedCategories.insert(target)
                notice = CleanupNotice(kind: .error, message: issue.detail)
            }
        }
    }

    func scanAll() {
        guard !isExecuting, !isPreparingAction else { return }
        let categories = FullScanPlan(
            includeSystemApplications: settings.includeSystemApplicationsInFullScan,
            includeDocker: settings.includeDockerInFullScan,
            includeCustomLocations: !settings.customScanRoots.isEmpty
        ).categories

        scanTask?.cancel()
        let scanID = UUID()
        activeScanID = scanID
        selectedItemIDs.removeAll()
        focusedItemID = nil
        isScanning = true
        scanningCategory = categories.first
        scanCompletedCount = 0
        scanTotalCount = categories.count + 1
        notice = nil

        let preferences = settings.snapshot
        let policy = ProtectionPolicy(customPaths: preferences.customProtectedPaths)
        scanTask = Task { [weak self] in
            guard let self else { return }
            defer { finishScan(id: scanID) }
            if !demoMode {
                hasFullDiskAccess = await scanCoordinator.beginScan()
                hasCheckedFullDiskAccess = true
                guard activeScanID == scanID, !Task.isCancelled else { return }
            }
            var failures: [String] = []
            let demoItems = demoMode ? DemoData.items() : [:]
            let quickCleanSources: Set<CleanupCategory> = [
                .caches, .browserData, .developerData, .logs,
            ]
            var didDeriveQuickClean = false

            for (index, category) in categories.enumerated() {
                if Task.isCancelled || activeScanID != scanID { return }
                scanningCategory = category
                scanIssues.removeValue(forKey: category)
                if category.requiresFullDiskAccess && !hasFullDiskAccess && !demoMode {
                    scanIssues[category] = CleanupScanIssueMapper.issue(
                        category: category,
                        error: FullDiskAccessError.required
                    )
                    scannedCategories.insert(category)
                    if !failures.contains("권한 필요") {
                        failures.append("권한 필요")
                    }
                    scanCompletedCount = index + 1 + (didDeriveQuickClean ? 1 : 0)
                    continue
                }
                do {
                    let items: [CleanupItem]
                    if demoMode {
                        try await Task.sleep(for: .milliseconds(55))
                        items = demoItems[category] ?? []
                    } else {
                        items = try await scanCoordinator.scan(
                            category: category,
                            preferences: preferences,
                            policy: policy
                        )
                    }
                    try Task.checkCancellation()
                    guard activeScanID == scanID else { return }
                    itemsByCategory[category] = items
                    scannedCategories.insert(category)
                    lastScannedAt[category] = Date()
                    scanIssues.removeValue(forKey: category)
                } catch is CancellationError {
                    return
                } catch {
                    guard activeScanID == scanID else { return }
                    scanIssues[category] = CleanupScanIssueMapper.issue(
                        category: category,
                        error: error
                    )
                    scannedCategories.insert(category)
                    failures.append(category.title)
                }
                if !didDeriveQuickClean,
                    quickCleanSources.allSatisfy({ scannedCategories.contains($0) })
                {
                    let sourceItems = quickCleanSources.flatMap {
                        itemsByCategory[$0] ?? []
                    }
                    itemsByCategory[.quickClean] = ScanCoordinator.makeQuickCleanItems(
                        from: sourceItems
                    )
                    scannedCategories.insert(.quickClean)
                    lastScannedAt[.quickClean] = Date()
                    scanIssues.removeValue(forKey: .quickClean)
                    didDeriveQuickClean = true
                }
                scanCompletedCount = index + 1 + (didDeriveQuickClean ? 1 : 0)
            }

            guard activeScanID == scanID else { return }
            notice = CleanupNotice(
                kind: failures.isEmpty ? .success : .warning,
                message: failures.isEmpty
                    ? "전체 스캔 완료"
                    : "일부 제외 · \(failures.joined(separator: ", "))"
            )
        }
    }

    func cancelScan() {
        activeScanID = nil
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanningCategory = nil
        scanCompletedCount = 0
        scanTotalCount = 0
    }

    func refreshStorage() async {
        do {
            storageSnapshot = try await scanCoordinator.storageSnapshot()
        } catch {
            notice = CleanupNotice(kind: .error, message: error.localizedDescription)
        }
    }

    private func finishScan(id: UUID) {
        guard activeScanID == id else { return }
        activeScanID = nil
        scanTask = nil
        isScanning = false
        scanningCategory = nil
    }
}
