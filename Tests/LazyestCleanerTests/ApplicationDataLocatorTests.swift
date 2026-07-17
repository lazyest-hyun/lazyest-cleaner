import Foundation
import XCTest
@testable import LazyestCleaner

final class ApplicationDataLocatorTests: XCTestCase {
    func testFindsOnlyExactApplicationDataPaths() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let exactCache = home.appending(path: "Library/Caches/com.example.editor")
        let exactSupport = home.appending(path: "Library/Application Support/Editor")
        let componentMatchedSupport = home.appending(path: "Library/Application Support/Example/Editor")
        let similarCache = home.appending(path: "Library/Caches/com.example.editor.helper")
        let similarSupport = home.appending(path: "Library/Application Support/Editor Beta")
        for directory in [exactCache, exactSupport, componentMatchedSupport, similarCache, similarSupport] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: 4_096).write(to: directory.appending(path: "data.bin"))
        }

        let applicationURL = home.appending(path: "Applications/Editor.app")
        let application = TestSupport.makeItem(
            url: applicationURL,
            category: .applications,
            kind: .application,
            name: "Editor",
            bundleIdentifier: "com.example.editor"
        )
        let fileScanner = FileScanner(home: home)
        let locator = ApplicationDataLocator(home: home, fileScanner: fileScanner)
        let items = try await locator.scanData(
            for: [application],
            policy: ProtectionPolicy(home: home)
        )

        XCTAssertEqual(
            Set(items.compactMap(\.url).map(\.standardizedFileURL.path)),
            [
                exactCache.standardizedFileURL.path,
                exactSupport.standardizedFileURL.path,
                componentMatchedSupport.standardizedFileURL.path,
            ])
        XCTAssertTrue(items.allSatisfy { $0.bundleIdentifier == "com.example.editor" })
        XCTAssertTrue(items.allSatisfy { $0.source == "Editor" })
    }

    func testAppliesCustomProtectionToLocatedApplicationData() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let cache = home.appending(path: "Library/Caches/com.example.editor")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data([1]).write(to: cache.appending(path: "data.bin"))

        let application = TestSupport.makeItem(
            url: home.appending(path: "Applications/Editor.app"),
            category: .applications,
            kind: .application,
            name: "Editor",
            bundleIdentifier: "com.example.editor"
        )
        let fileScanner = FileScanner(home: home)
        let locator = ApplicationDataLocator(home: home, fileScanner: fileScanner)
        let items = try await locator.scanData(
            for: [application],
            policy: ProtectionPolicy(customPaths: [cache], home: home)
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.protectedReason, "사용자 보호")
        XCTAssertFalse(items.first?.isSelectable == true)
    }

    func testUsesExplicitManifestForNonstandardApplicationData() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let xcodeData = home.appending(path: "Library/Developer/Xcode")
        try FileManager.default.createDirectory(at: xcodeData, withIntermediateDirectories: true)
        try Data([1]).write(to: xcodeData.appending(path: "state.bin"))

        let application = TestSupport.makeItem(
            url: home.appending(path: "Applications/Xcode.app"),
            category: .applications,
            kind: .application,
            name: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode"
        )
        let fileScanner = FileScanner(home: home)
        let locator = ApplicationDataLocator(home: home, fileScanner: fileScanner)
        let items = try await locator.scanData(
            for: [application],
            policy: ProtectionPolicy(home: home)
        )

        XCTAssertTrue(items.contains { $0.url?.standardizedFileURL == xcodeData.standardizedFileURL })
    }

    func testDoesNotBlockOnAnUnresolvedDirectorySize() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let cache = home.appending(path: "Library/Caches/com.example.editor")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4_096).write(to: cache.appending(path: "data.bin"))

        let application = TestSupport.makeItem(
            url: home.appending(path: "Applications/Editor.app"),
            category: .applications,
            kind: .application,
            name: "Editor",
            bundleIdentifier: "com.example.editor"
        )
        let fileScanner = FileScanner(home: home, diskUsage: EmptyDiskUsage())
        let locator = ApplicationDataLocator(home: home, fileScanner: fileScanner)
        let items = try await locator.scanData(
            for: [application],
            policy: ProtectionPolicy(home: home)
        )

        XCTAssertEqual(items.first { $0.url?.standardizedFileURL == cache.standardizedFileURL }?.size, 0)
    }

    func testDeduplicatesCaseVariantsThatResolveToTheSameDirectory() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let support = home.appending(path: "Library/Application Support/vrew")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let application = TestSupport.makeItem(
            url: home.appending(path: "Applications/Vrew.app"),
            category: .applications,
            kind: .application,
            name: "Vrew",
            bundleIdentifier: "com.voyagerx.vrew"
        )
        let fileScanner = FileScanner(home: home, diskUsage: EmptyDiskUsage())
        let locator = ApplicationDataLocator(home: home, fileScanner: fileScanner)
        let items = try await locator.scanData(
            for: [application],
            policy: ProtectionPolicy(home: home)
        )

        let supportMatches = items.filter {
            $0.url?.standardizedFileURL.path.lowercased() == support.standardizedFileURL.path.lowercased()
        }
        XCTAssertEqual(supportMatches.count, 1)
    }
}

private actor EmptyDiskUsage: DiskUsageMeasuring {
    func sizes(of urls: [URL]) async throws -> [String: Int64] {
        [:]
    }
}
