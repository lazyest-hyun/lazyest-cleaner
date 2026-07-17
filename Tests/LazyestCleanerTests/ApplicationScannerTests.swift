import Foundation
import XCTest
@testable import LazyestCleaner

final class ApplicationScannerTests: XCTestCase {
    func testFindsAppsInSubdirectoriesWithoutCountingNestedHelpers() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let applications = home.appending(path: "Applications")
        let utilities = applications.appending(path: "Utilities")
        try FileManager.default.createDirectory(at: utilities, withIntermediateDirectories: true)

        _ = try makeBundle(name: "Top App", identifier: "com.example.top", parent: applications)
        let nested = try makeBundle(name: "Nested App", identifier: "com.example.nested", parent: utilities)
        _ = try makeBundle(
            name: "Helper",
            identifier: "com.example.nested.helper",
            parent: nested.appending(path: "Contents/Helpers")
        )

        let fileScanner = FileScanner(home: home)
        let scanner = ApplicationScanner(
            home: home,
            fileScanner: fileScanner,
            applicationSizer: FixedApplicationSizer(size: 4_096),
            applicationRoots: [ApplicationSearchRoot(url: applications, source: "테스트 앱")]
        )
        let items = try await scanner.scanApplications(policy: ProtectionPolicy(home: home))

        XCTAssertEqual(Set(items.map(\.name)), ["Top App", "Nested App"])
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.source == "테스트 앱" })
        XCTAssertTrue(items.allSatisfy { $0.size == 4_096 })
    }

    func testSeparatesInstalledAndSystemApplications() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let installedRoot = fixture.appending(path: "Applications")
        let systemRoot = fixture.appending(path: "System/Applications")
        try FileManager.default.createDirectory(at: installedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systemRoot, withIntermediateDirectories: true)

        _ = try makeBundle(name: "Installed", identifier: "com.example.installed", parent: installedRoot)
        _ = try makeBundle(name: "System Tool", identifier: "com.example.system", parent: systemRoot)

        let fileScanner = FileScanner(home: home)
        let scanner = ApplicationScanner(
            home: home,
            fileScanner: fileScanner,
            applicationSizer: FixedApplicationSizer(size: 4_096),
            applicationRoots: [
                ApplicationSearchRoot(url: installedRoot, source: "설치 앱"),
                ApplicationSearchRoot(url: systemRoot, source: "시스템 앱", kind: .system),
            ]
        )
        let policy = ProtectionPolicy(home: home)
        let installed = try await scanner.scanApplications(system: false, policy: policy)
        let system = try await scanner.scanApplications(system: true, policy: policy)

        XCTAssertEqual(installed.map(\.name), ["Installed"])
        XCTAssertEqual(installed.first?.category, .applications)
        XCTAssertTrue(installed.first?.isSelectable == true)
        XCTAssertEqual(system.map(\.name), ["System Tool"])
        XCTAssertEqual(system.first?.category, .systemApplications)
        XCTAssertEqual(system.first?.protectedReason, "시스템 앱")
        XCTAssertFalse(system.first?.isSelectable == true)
    }

    private func makeBundle(name: String, identifier: String, parent: URL) throws -> URL {
        let bundle = parent.appending(path: "\(name).app")
        let contents = bundle.appending(path: "Contents")
        let macOS = contents.appending(path: "MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": name,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        try Data(repeating: 0x41, count: 4_096).write(to: macOS.appending(path: name))
        return bundle
    }
}

private struct FixedApplicationSizer: ApplicationSizing {
    let size: Int64

    func sizes(for requests: [ApplicationSizeRequest]) async throws -> [String: Int64] {
        Dictionary(uniqueKeysWithValues: requests.map { ($0.path, size) })
    }
}
