import Foundation
import XCTest
@testable import LazyestCleaner

final class CleanupPreflightTests: XCTestCase {
    func testAllowsRegularFileInsideConfiguredHome() throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let file = home.appending(path: "Downloads/file.bin")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data([1])))

        let reason = CleanupPreflight.failureReason(
            for: TestSupport.makeItem(url: file),
            action: .moveToTrash,
            preferences: CleanupPreferences(),
            policy: ProtectionPolicy(home: home),
            homeURL: home
        )
        XCTAssertNil(reason)
    }

    func testRejectsOutsideHomeMissingProtectedAndSymbolicLink() throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let outside = fixture.appending(path: "outside.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: outside.path, contents: Data([1])))
        let policy = ProtectionPolicy(home: home)

        XCTAssertEqual(
            CleanupPreflight.failureReason(
                for: TestSupport.makeItem(url: outside),
                action: .moveToTrash,
                preferences: CleanupPreferences(),
                policy: policy,
                homeURL: home
            ),
            "허용 범위 밖"
        )

        let missing = home.appending(path: "missing.bin")
        XCTAssertEqual(
            CleanupPreflight.failureReason(
                for: TestSupport.makeItem(url: missing),
                action: .moveToTrash,
                preferences: CleanupPreferences(),
                policy: policy,
                homeURL: home
            ),
            "항목 없음"
        )

        let target = home.appending(path: "target.bin")
        let link = home.appending(path: "link.bin")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: target.path, contents: Data([1])))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(
            CleanupPreflight.failureReason(
                for: TestSupport.makeItem(url: link),
                action: .moveToTrash,
                preferences: CleanupPreferences(),
                policy: policy,
                homeURL: home
            ),
            "심볼릭 링크"
        )
    }

    func testImmediateRemovalRequiresSettingAndSafeKind() throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let file = home.appending(path: "Library/Caches/cache.bin")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data([1])))
        let policy = ProtectionPolicy(home: home)

        XCTAssertEqual(
            CleanupPreflight.failureReason(
                for: TestSupport.makeItem(url: file, kind: .cache),
                action: .removeImmediately,
                preferences: CleanupPreferences(),
                policy: policy,
                homeURL: home
            ),
            "즉시 삭제 꺼짐"
        )

        var enabled = CleanupPreferences()
        enabled.allowImmediateRemoval = true
        XCTAssertNil(
            CleanupPreflight.failureReason(
                for: TestSupport.makeItem(url: file, kind: .cache),
                action: .removeImmediately,
                preferences: enabled,
                policy: policy,
                homeURL: home
            )
        )
        XCTAssertEqual(
            CleanupPreflight.failureReason(
                for: TestSupport.makeItem(url: file, kind: .file),
                action: .removeImmediately,
                preferences: enabled,
                policy: policy,
                homeURL: home
            ),
            "즉시 삭제 불가"
        )
    }

    func testDockerItemRequiresDockerAction() {
        let item = TestSupport.makeItem(
            url: nil,
            category: .docker,
            kind: .dockerBuildCache,
            operation: .docker(.buildCache)
        )
        let policy = ProtectionPolicy()

        XCTAssertEqual(
            CleanupPreflight.failureReason(
                for: item,
                action: .moveToTrash,
                preferences: CleanupPreferences(),
                policy: policy
            ),
            "Docker 전용 액션 필요"
        )
        XCTAssertNil(
            CleanupPreflight.failureReason(
                for: item,
                action: .runDockerCleanup,
                preferences: CleanupPreferences(),
                policy: policy
            )
        )
    }

    func testApplicationAndTrashActionsAcceptOnlyTheirOwnItemKinds() throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let app = home.appending(path: "Applications/Editor.app")
        let data = home.appending(path: "Library/Caches/com.example.editor")
        let trash = home.appending(path: ".Trash/file.bin")
        for url in [app, data] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(
            at: trash.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: trash.path, contents: Data([1])))

        let policy = ProtectionPolicy(home: home)
        let preferences = CleanupPreferences()
        let appItem = TestSupport.makeItem(url: app, category: .applications, kind: .application)
        let dataItem = TestSupport.makeItem(url: data, category: .leftovers, kind: .appLeftover)
        let trashItem = TestSupport.makeItem(
            url: trash,
            category: .trash,
            kind: .trash,
            operation: .removeImmediately
        )

        XCTAssertNil(
            CleanupPreflight.failureReason(
                for: dataItem, action: .removeAppData, preferences: preferences, policy: policy, homeURL: home))
        XCTAssertNil(
            CleanupPreflight.failureReason(
                for: appItem, action: .removeApplicationOnly, preferences: preferences, policy: policy, homeURL: home))
        XCTAssertNil(
            CleanupPreflight.failureReason(
                for: appItem, action: .uninstallApplication, preferences: preferences, policy: policy, homeURL: home))
        XCTAssertNil(
            CleanupPreflight.failureReason(
                for: dataItem, action: .uninstallApplication, preferences: preferences, policy: policy, homeURL: home))
        XCTAssertNil(
            CleanupPreflight.failureReason(
                for: trashItem, action: .deletePermanently, preferences: preferences, policy: policy, homeURL: home))

        XCTAssertEqual(
            CleanupPreflight.failureReason(
                for: appItem, action: .removeAppData, preferences: preferences, policy: policy, homeURL: home),
            "앱 데이터만 가능")
        XCTAssertEqual(
            CleanupPreflight.failureReason(
                for: dataItem, action: .removeApplicationOnly, preferences: preferences, policy: policy, homeURL: home),
            "앱만 가능")
        XCTAssertEqual(
            CleanupPreflight.failureReason(
                for: appItem, action: .moveToTrash, preferences: preferences, policy: policy, homeURL: home),
            "앱 전용 액션 필요")
        XCTAssertEqual(
            CleanupPreflight.failureReason(
                for: appItem, action: .deletePermanently, preferences: preferences, policy: policy, homeURL: home),
            "휴지통 항목만 가능")
    }
}
