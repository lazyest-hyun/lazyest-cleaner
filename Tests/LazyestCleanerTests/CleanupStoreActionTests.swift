import Foundation
import XCTest
@testable import LazyestCleaner

@MainActor
final class CleanupStoreActionTests: XCTestCase {
    func testOverviewCandidateBytesExcludeProtectedItems() async {
        let suiteName = "CleanupStoreOverviewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CleanupStore(settings: AppSettings(defaults: defaults), demoMode: true)
        await store.start()

        let overviewItems = store.overviewCategories.flatMap {
            store.itemsByCategory[$0] ?? []
        }
        let expected =
            overviewItems
            .filter(\.isSelectable)
            .reduce(Int64(0)) { $0 + $1.size }
        let allBytes =
            overviewItems
            .reduce(Int64(0)) { $0 + $1.size }

        XCTAssertEqual(store.totalCandidateBytes, expected)
        XCTAssertLessThan(store.totalCandidateBytes, allBytes)

        let baseline = store.totalCandidateBytes
        let source = store.itemsByCategory[.applications]!.first { $0.isSelectable }!
        let duplicate = CleanupItem(
            id: "duplicate:\(source.id)",
            category: .oldFiles,
            kind: source.kind,
            name: source.name,
            url: source.url,
            size: source.size,
            modifiedAt: source.modifiedAt,
            risk: source.risk,
            recommendation: source.recommendation,
            operation: source.operation,
            source: source.source,
            detail: source.detail,
            protectedReason: source.protectedReason,
            bundleIdentifier: source.bundleIdentifier,
            duplicateGroupID: source.duplicateGroupID,
            metadata: source.metadata
        )
        store.itemsByCategory[.oldFiles, default: []].append(duplicate)
        XCTAssertEqual(store.totalCandidateBytes, baseline)
    }

    func testCategorySpecificPrimaryActions() async {
        let suiteName = "CleanupStoreActionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CleanupStore(settings: AppSettings(defaults: defaults), demoMode: true)
        await store.start()

        store.selectCategory(.applications)
        let installed = store.currentItems.first { $0.isSelectable }!
        store.setSelection([installed.id])
        XCTAssertTrue(store.resolution(for: .removeApplicationOnly).isEnabled)
        XCTAssertTrue(store.resolution(for: .removeAppData).isEnabled)
        XCTAssertTrue(store.resolution(for: .uninstallApplication).isEnabled)
        XCTAssertFalse(store.resolution(for: .moveToTrash).isEnabled)

        store.selectCategory(.systemApplications)
        let system = store.currentItems.first!
        store.setSelection([system.id])
        XCTAssertFalse(store.resolution(for: .removeAppData).isEnabled)
        XCTAssertFalse(store.resolution(for: .uninstallApplication).isEnabled)
        XCTAssertTrue(store.resolution(for: .reveal).isEnabled)
        XCTAssertFalse(store.resolution(for: .removeApplicationOnly).isEnabled)

        store.selectCategory(.trash)
        let trash = store.currentItems.first!
        store.setSelection([trash.id])
        XCTAssertTrue(store.resolution(for: .deletePermanently).isEnabled)
        XCTAssertFalse(store.resolution(for: .moveToTrash).isEnabled)
    }

    func testApplicationOnlyActionConfirmsOnlyTheSelectedApplication() async throws {
        let suiteName = "CleanupStoreApplicationOnlyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CleanupStore(settings: AppSettings(defaults: defaults), demoMode: true)
        await store.start()
        store.selectCategory(.applications)
        let applications = store.currentItems.filter(\.isSelectable)
        let first = try XCTUnwrap(applications.first)
        let second = try XCTUnwrap(applications.dropFirst().first)
        store.setSelection([first.id])

        let contextResolution = store.resolution(
            for: .removeApplicationOnly,
            itemIDs: [second.id]
        )
        XCTAssertTrue(contextResolution.isEnabled)
        XCTAssertEqual(contextResolution.items.map(\.id), [second.id])
        XCTAssertEqual(store.selectedItemIDs, [first.id])

        store.requestAction(.removeApplicationOnly, itemIDs: [second.id])
        let request = try XCTUnwrap(store.pendingConfirmation)
        XCTAssertEqual(request.action, .removeApplicationOnly)
        XCTAssertEqual(request.items.map(\.id), [second.id])
        XCTAssertTrue(request.items.allSatisfy { $0.kind == .application })
        XCTAssertEqual(store.selectedItemIDs, [second.id])
    }

    func testApplicationActionsPrepareDifferentConfirmationItems() async throws {
        let suiteName = "CleanupStoreActionPreparationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CleanupStore(settings: AppSettings(defaults: defaults), demoMode: true)
        await store.start()
        store.selectCategory(.applications)
        let application = store.currentItems.first { $0.isSelectable }!
        store.setSelection([application.id])

        store.requestAction(.removeAppData)
        try await Task.sleep(for: .milliseconds(260))
        let dataOnly = try XCTUnwrap(store.pendingConfirmation)
        XCTAssertEqual(dataOnly.action, .removeAppData)
        XCTAssertTrue(dataOnly.items.allSatisfy { $0.kind == .appLeftover })
        store.dismissConfirmation()

        store.requestAction(.uninstallApplication)
        try await Task.sleep(for: .milliseconds(260))
        let uninstall = try XCTUnwrap(store.pendingConfirmation)
        XCTAssertEqual(uninstall.action, .uninstallApplication)
        XCTAssertTrue(uninstall.items.contains { $0.kind == .application })
        XCTAssertTrue(uninstall.items.contains { $0.kind == .appLeftover })
    }

    func testReplacingScanKeepsNewScanProgressUntilCompletion() async throws {
        let suiteName = "CleanupStoreScanLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CleanupStore(settings: AppSettings(defaults: defaults), demoMode: true)
        await store.start()

        store.scan(.applications)
        try await Task.sleep(for: .milliseconds(20))
        store.scanAll()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(store.isScanning)
        XCTAssertNotNil(store.scanningCategory)

        for _ in 0..<30 where store.isScanning {
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertFalse(store.isScanning)
        XCTAssertNil(store.scanningCategory)
        XCTAssertEqual(store.scanCompletedCount, store.scanTotalCount)
        XCTAssertEqual(store.notice?.message, "전체 스캔 완료")
    }
}
