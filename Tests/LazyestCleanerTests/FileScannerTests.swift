import Foundation
import XCTest
@testable import LazyestCleaner

final class FileScannerTests: XCTestCase {
    func testDedicatedBrowserAndDeveloperCachesDoNotOverlapGenericCaches() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let chrome = home.appending(path: "Library/Caches/Google/Chrome/data.bin")
        let updater = home.appending(path: "Library/Caches/Google/Updater/data.bin")
        let homebrew = home.appending(path: "Library/Caches/Homebrew/data.bin")
        let regular = home.appending(path: "Library/Caches/com.example.editor/data.bin")
        for url in [chrome, updater, homebrew, regular] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(repeating: 1, count: 1_100_000).write(to: url)
        }

        let scanner = FileScanner(home: home)
        let policy = ProtectionPolicy(home: home)
        let generic = try await scanner.scan(
            category: .caches,
            preferences: CleanupPreferences(),
            policy: policy
        )
        let browser = try await scanner.scan(
            category: .browserData,
            preferences: CleanupPreferences(),
            policy: policy
        )
        let genericPaths = Set(generic.compactMap { $0.url?.standardizedFileURL.path })
        let browserPaths = Set(browser.compactMap { $0.url?.standardizedFileURL.path })

        XCTAssertTrue(genericPaths.contains(updater.deletingLastPathComponent().path))
        XCTAssertTrue(genericPaths.contains(regular.deletingLastPathComponent().path))
        XCTAssertFalse(genericPaths.contains(home.appending(path: "Library/Caches/Google").path))
        XCTAssertFalse(genericPaths.contains(homebrew.deletingLastPathComponent().path))
        XCTAssertTrue(browserPaths.contains(chrome.deletingLastPathComponent().path))
        XCTAssertTrue(genericPaths.isDisjoint(with: browserPaths))
    }

    func testDiagnosticReportsAreNotReturnedWithNestedChildren() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let diagnostic = home.appending(path: "Library/Logs/DiagnosticReports/crash.log")
        let appLog = home.appending(path: "Library/Logs/Example/editor.log")
        for url in [diagnostic, appLog] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(repeating: 2, count: 1_100_000).write(to: url)
        }

        let scanner = FileScanner(home: home)
        let items = try await scanner.scan(
            category: .logs,
            preferences: CleanupPreferences(),
            policy: ProtectionPolicy(home: home)
        )
        let paths = Set(items.compactMap { $0.url?.standardizedFileURL.path })

        XCTAssertTrue(paths.contains(diagnostic.deletingLastPathComponent().path))
        XCTAssertTrue(paths.contains(appLog.deletingLastPathComponent().path))
        XCTAssertFalse(paths.contains(diagnostic.path))
        XCTAssertFalse(paths.contains(appLog.path))
    }

    func testDownloadsClassifiesInstallersAndAppliesProtection() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let downloads = home.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let installer = downloads.appending(path: "Tool.dmg")
        let archive = downloads.appending(path: "project.zip")
        try Data(repeating: 1, count: 1_100_000).write(to: installer)
        try Data(repeating: 2, count: 1_100_000).write(to: archive)

        let scanner = FileScanner(home: home)
        let items = try await scanner.scan(
            category: .downloads,
            preferences: CleanupPreferences(),
            policy: ProtectionPolicy(customPaths: [archive], home: home)
        )

        let installerItem = try XCTUnwrap(items.first { $0.name == "Tool.dmg" })
        XCTAssertEqual(installerItem.kind, .installer)
        XCTAssertEqual(installerItem.risk, .safe)
        XCTAssertEqual(installerItem.recommendation, .recommended)

        let protectedItem = try XCTUnwrap(items.first { $0.name == "project.zip" })
        XCTAssertTrue(protectedItem.isProtected)
        XCTAssertEqual(protectedItem.recommendation, .avoid)
    }

    func testDeniedDownloadsReturnsWithoutStartingSizeMeasurement() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let downloads = home.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let diskUsage = UnexpectedDiskUsageMeasurer()
        let scanner = FileScanner(
            home: home,
            diskUsage: diskUsage,
            directoryAccess: DeniedDirectoryAccess()
        )

        do {
            _ = try await scanner.scan(
                category: .downloads,
                preferences: CleanupPreferences(),
                policy: ProtectionPolicy(home: home)
            )
            XCTFail("expected permission error")
        } catch let error as DirectoryAccessError {
            XCTAssertEqual(error.localizedDescription, "다운로드 접근 권한 필요")
        }

        let callCount = await diskUsage.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testFileInventoryReusesSnapshotUntilInvalidated() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let documents = home.appending(path: "Documents")
        try FileManager.default.createDirectory(
            at: documents,
            withIntermediateDirectories: true
        )
        let file = documents.appending(path: "report.bin")
        try Data(repeating: 3, count: 2_048).write(to: file)
        let inventory = FileInventoryService()
        let policy = ProtectionPolicy(home: home)

        let initial = try await inventory.records(
            roots: [documents],
            includeHiddenFiles: false,
            policy: policy
        )
        try FileManager.default.removeItem(at: file)
        let cached = try await inventory.records(
            roots: [documents],
            includeHiddenFiles: false,
            policy: policy
        )
        await inventory.invalidate()
        let refreshed = try await inventory.records(
            roots: [documents],
            includeHiddenFiles: false,
            policy: policy
        )

        XCTAssertEqual(initial.count, 1)
        XCTAssertEqual(cached.count, 1)
        XCTAssertTrue(refreshed.isEmpty)
    }

    func testFileInventorySkipsPackageContents() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let pictures = home.appending(path: "Pictures")
        let packageFile = pictures.appending(path: "Library.app/Contents/asset.bin")
        let regularFile = pictures.appending(path: "export.jpg")
        try FileManager.default.createDirectory(
            at: packageFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([1]).write(to: packageFile)
        try Data([2]).write(to: regularFile)

        let inventory = FileInventoryService()
        let records = try await inventory.records(
            roots: [pictures],
            includeHiddenFiles: false,
            policy: ProtectionPolicy(home: home)
        )

        XCTAssertEqual(records.map(\.url.standardizedFileURL.path), [regularFile.path])
    }
}

private struct DeniedDirectoryAccess: DirectoryAccessChecking {
    func canEnumerate(_ url: URL) async -> Bool { false }
}

private actor UnexpectedDiskUsageMeasurer: DiskUsageMeasuring {
    private(set) var callCount = 0

    func sizes(of urls: [URL]) async throws -> [String: Int64] {
        callCount += 1
        return [:]
    }
}
