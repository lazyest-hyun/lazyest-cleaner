import AppKit
import Foundation

extension CleanupStore {
    func prepareApplicationAction(
        _ action: CleanupActionID,
        applications: [CleanupItem]
    ) {
        guard !isPreparingAction, !isExecuting, !applications.isEmpty else { return }
        actionPreparationTask?.cancel()
        isPreparingAction = true
        notice = nil

        let policy = ProtectionPolicy(customPaths: settings.customProtectedPaths)
        actionPreparationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isPreparingAction = false
                actionPreparationTask = nil
            }

            do {
                let locatedData: [CleanupItem]
                if demoMode {
                    try await Task.sleep(for: .milliseconds(180))
                    locatedData = demoApplicationDataItems(for: applications)
                } else {
                    locatedData = try await scanCoordinator.applicationDataItems(
                        for: applications,
                        policy: policy
                    )
                }
                try Task.checkCancellation()

                let applicationData = locatedData.filter(\.isSelectable)
                if action == .removeAppData && applicationData.isEmpty {
                    notice = CleanupNotice(
                        kind: .warning,
                        message: "삭제 가능한 앱 데이터 없음"
                    )
                    return
                }

                let items =
                    action == .uninstallApplication
                    ? applications + applicationData
                    : applicationData
                pendingConfirmation = CleanupConfirmationRequest(
                    action: action,
                    items: items
                )
            } catch is CancellationError {
                return
            } catch {
                notice = CleanupNotice(kind: .error, message: error.localizedDescription)
            }
        }
    }

    func execute(_ request: CleanupConfirmationRequest) {
        guard !isExecuting else { return }
        isExecuting = true
        notice = nil
        let preferences = settings.snapshot
        let policy = ProtectionPolicy(customPaths: preferences.customProtectedPaths)

        executionTask = Task { [weak self] in
            guard let self else { return }
            let report: CleanupExecutionReport
            if demoMode {
                try? await Task.sleep(for: .milliseconds(350))
                report = CleanupExecutionReport(
                    action: request.action,
                    itemCount: request.items.count,
                    bytes: request.bytes,
                    succeeded: request.items.count,
                    failures: []
                )
                removeDemoItems(request.items)
            } else {
                report = await executor.execute(
                    action: request.action,
                    items: request.items,
                    preferences: preferences,
                    policy: policy
                )
            }

            lastReport = report
            if demoMode {
                history.insert(report.historyEntry, at: 0)
            } else {
                do {
                    history = try await historyRepository.append(report.historyEntry)
                } catch {
                    notice = CleanupNotice(kind: .error, message: error.localizedDescription)
                }
            }

            selectedItemIDs.removeAll()
            focusedItemID = nil
            isExecuting = false
            let cleanedBytes = report.failures.isEmpty ? report.bytes : 0
            notice = CleanupNotice(
                kind: report.failures.isEmpty ? .success : .warning,
                message: report.failures.isEmpty
                    ? "\(report.succeeded)개 · \(DisplayFormatting.bytes(cleanedBytes))"
                    : "완료 \(report.succeeded) · 실패 \(report.failures.count)"
            )

            if !demoMode {
                scan(selectedCategory)
                await refreshStorage()
            }
        }
    }

    func reveal(_ item: CleanupItem?) {
        guard let url = item?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func demoApplicationDataItems(
        for applications: [CleanupItem]
    ) -> [CleanupItem] {
        applications.compactMap { application in
            guard let bundleIdentifier = application.bundleIdentifier else { return nil }
            let url = URL(fileURLWithPath: "/Users/demo/Library/Application Support")
                .appending(path: bundleIdentifier)
            return CleanupItem(
                id: CleanupItem.stableID(prefix: "appData", value: url.path),
                category: .leftovers,
                kind: .appLeftover,
                name: "Application Support/\(bundleIdentifier)",
                url: url,
                size: 384_000_000,
                modifiedAt: Date(),
                risk: .sensitive,
                recommendation: .avoid,
                operation: .recycle,
                source: application.name,
                detail: nil,
                protectedReason: nil,
                bundleIdentifier: bundleIdentifier,
                duplicateGroupID: nil,
                metadata: ["앱": application.name]
            )
        }
    }

    private func removeDemoItems(_ items: [CleanupItem]) {
        let ids = Set(items.map(\.id))
        guard var categoryItems = itemsByCategory[selectedCategory] else { return }
        categoryItems.removeAll { ids.contains($0.id) }
        itemsByCategory[selectedCategory] = categoryItems
    }
}
