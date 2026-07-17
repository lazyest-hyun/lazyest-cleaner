import Foundation
import XCTest
@testable import LazyestCleaner

final class DuplicateScannerTests: XCTestCase {
    func testHashesEqualSizedFilesAndProtectsOneReferenceCopy() async throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let documents = home.appending(path: "Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let contents = Data(repeating: 0x41, count: 16_384)
        try contents.write(to: documents.appending(path: "a.bin"))
        try contents.write(to: documents.appending(path: "b.bin"))

        var preferences = CleanupPreferences()
        preferences.duplicateMinimumSize = 1
        let scanner = DuplicateScanner(home: home)
        let items = try await scanner.scan(
            preferences: preferences,
            policy: ProtectionPolicy(home: home)
        )

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.filter { $0.kind == .duplicateOriginal }.count, 1)
        XCTAssertEqual(items.filter { $0.kind == .duplicateCopy }.count, 1)
        XCTAssertEqual(items.filter(\.isProtected).count, 1)
        XCTAssertEqual(Set(items.compactMap(\.duplicateGroupID)).count, 1)
    }
}
