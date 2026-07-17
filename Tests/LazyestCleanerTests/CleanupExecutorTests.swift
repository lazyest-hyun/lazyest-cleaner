import Foundation
import XCTest
@testable import LazyestCleaner

final class CleanupExecutorTests: XCTestCase {
    func testImmediateRemovalDeletesOnlyPreflightApprovedCache() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let cache = home.appending(path: "Library/Caches/cache.bin")
        let document = home.appending(path: "Documents/keep.bin")
        for url in [cache, document] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            XCTAssertTrue(
                FileManager.default.createFile(
                    atPath: url.path,
                    contents: Data([1])
                ))
        }

        var preferences = CleanupPreferences()
        preferences.allowImmediateRemoval = true
        let executor = CleanupExecutor()
        let report = await executor.execute(
            action: .removeImmediately,
            items: [
                TestSupport.makeItem(url: cache, kind: .cache),
                TestSupport.makeItem(url: document, kind: .file),
            ],
            preferences: preferences,
            policy: ProtectionPolicy(home: home)
        )

        XCTAssertEqual(report.succeeded, 1)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: document.path))
    }

    func testUninstallRecyclesApplicationAndAssociatedDataTogether() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let applicationURL = home.appending(path: "Applications/Editor.app")
        let dataURL = home.appending(path: "Library/Application Support/com.example.editor")
        try FileManager.default.createDirectory(at: applicationURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)

        let bundleIdentifier = "com.example.executor-test.\(UUID().uuidString)"
        let application = TestSupport.makeItem(
            url: applicationURL,
            category: .applications,
            kind: .application,
            name: "Editor",
            bundleIdentifier: bundleIdentifier
        )
        let data = TestSupport.makeItem(
            url: dataURL,
            category: .leftovers,
            kind: .appLeftover,
            name: "Application Support/com.example.editor",
            bundleIdentifier: bundleIdentifier
        )
        let recycler = RecordingRecycler()
        let executor = CleanupExecutor(recycler: recycler)

        let report = await executor.execute(
            action: .uninstallApplication,
            items: [application, data],
            preferences: CleanupPreferences(),
            policy: ProtectionPolicy(home: home)
        )

        XCTAssertEqual(report.succeeded, 2)
        XCTAssertTrue(report.failures.isEmpty)
        let received = await recycler.receivedURLs()
        let receivedPaths = Set(received.map(\.standardizedFileURL.path))
        XCTAssertEqual(
            receivedPaths,
            [
                applicationURL.standardizedFileURL.path,
                dataURL.standardizedFileURL.path,
            ])
    }

    func testApplicationOnlyActionNeverIncludesAssociatedData() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let applicationURL = home.appending(path: "Applications/Editor.app")
        let dataURL = home.appending(path: "Library/Application Support/com.example.editor")
        try FileManager.default.createDirectory(at: applicationURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)

        let application = TestSupport.makeItem(
            url: applicationURL,
            category: .applications,
            kind: .application,
            bundleIdentifier: "com.example.executor-app-only"
        )
        let recycler = RecordingRecycler()
        let executor = CleanupExecutor(recycler: recycler)
        let report = await executor.execute(
            action: .removeApplicationOnly,
            items: [application],
            preferences: CleanupPreferences(),
            policy: ProtectionPolicy(home: home)
        )

        XCTAssertEqual(report.succeeded, 1)
        XCTAssertTrue(report.failures.isEmpty)
        let received = await recycler.receivedURLs()
        let receivedPaths = Set(received.map(\.standardizedFileURL.path))
        XCTAssertEqual(receivedPaths, [applicationURL.standardizedFileURL.path])
        XCTAssertFalse(receivedPaths.contains(dataURL.standardizedFileURL.path))
    }

    func testPartialRecycleMappingIsReportedAsFailure() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let firstURL = home.appending(path: "Downloads/first.bin")
        let secondURL = home.appending(path: "Downloads/second.bin")
        try FileManager.default.createDirectory(
            at: firstURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([1]).write(to: firstURL)
        try Data([2]).write(to: secondURL)

        let executor = CleanupExecutor(recycler: PartialRecycler())
        let report = await executor.execute(
            action: .moveToTrash,
            items: [
                TestSupport.makeItem(url: firstURL),
                TestSupport.makeItem(url: secondURL),
            ],
            preferences: CleanupPreferences(),
            policy: ProtectionPolicy(home: home)
        )

        XCTAssertEqual(report.succeeded, 1)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(report.failures.first?.name, secondURL.lastPathComponent)
    }
}

private actor RecordingRecycler: FileRecycling {
    private var urls: [URL] = []

    func recycle(_ urls: [URL]) async throws -> [URL: URL] {
        self.urls = urls
        return Dictionary(
            uniqueKeysWithValues: urls.map { url in
                (url, URL(fileURLWithPath: "/tmp").appending(path: url.lastPathComponent))
            })
    }

    func receivedURLs() -> [URL] {
        urls
    }
}

private struct PartialRecycler: FileRecycling {
    func recycle(_ urls: [URL]) async throws -> [URL: URL] {
        guard let first = urls.first else { return [:] }
        return [first: URL(fileURLWithPath: "/tmp").appending(path: first.lastPathComponent)]
    }
}
