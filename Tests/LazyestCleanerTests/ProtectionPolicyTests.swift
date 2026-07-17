import XCTest
@testable import LazyestCleaner

final class ProtectionPolicyTests: XCTestCase {
    func testCustomRuleProtectsPathChildrenAndDeletionAncestors() throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let protected = home.appending(path: "Documents/Keep")
        let policy = ProtectionPolicy(customPaths: [protected], home: home)

        XCTAssertTrue(policy.decision(for: protected).isProtected)
        XCTAssertTrue(policy.decision(for: protected.appending(path: "child.txt")).isProtected)
        XCTAssertTrue(policy.decision(for: home.appending(path: "Documents")).isProtected)
        XCTAssertFalse(policy.decision(for: home.appending(path: "Downloads/file.txt")).isProtected)
    }

    func testHomeChildrenRemainEligibleButHomeAndCloudStorageAreProtected() throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let policy = ProtectionPolicy(home: home)

        XCTAssertTrue(policy.decision(for: home).isProtected)
        XCTAssertFalse(policy.decision(for: home.appending(path: "Documents/file.txt")).isProtected)
        XCTAssertTrue(policy.decision(for: home.appending(path: "Library/CloudStorage/Drive/file.txt")).isProtected)
    }

    func testScannerOnlySkipsInsideProtectedSubtree() throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let protected = home.appending(path: "Documents/Keep")
        let policy = ProtectionPolicy(customPaths: [protected], home: home)

        XCTAssertFalse(policy.shouldSkipDescendants(of: home.appending(path: "Documents")))
        XCTAssertTrue(policy.shouldSkipDescendants(of: protected))
        XCTAssertTrue(policy.shouldSkipDescendants(of: protected.appending(path: "Nested")))
    }

    func testDockerVMAndItsDeletionAncestorsStayProtected() throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let policy = ProtectionPolicy(home: home)
        let dockerVM = home.appending(path: "Library/Containers/com.docker.docker")

        XCTAssertEqual(policy.decision(for: dockerVM).reason, "Docker 전용 정리")
        XCTAssertEqual(policy.decision(for: dockerVM.appending(path: "Data/vms/0")).reason, "Docker 전용 정리")
        XCTAssertEqual(policy.decision(for: home.appending(path: "Library/Containers")).reason, "Docker 전용 정리")
    }

    func testCriticalPersonalStoresRemainProtected() throws {
        let fixture = try TestSupport.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "Home")
        let policy = ProtectionPolicy(home: home)

        XCTAssertEqual(
            policy.decision(for: home.appending(path: "Library/Keychains/login.keychain-db")).reason,
            "Keychain 데이터"
        )
        XCTAssertEqual(
            policy.decision(for: home.appending(path: "Library/Mail/V10")).reason,
            "Mail 데이터"
        )
        XCTAssertEqual(
            policy.decision(for: home.appending(path: "Library/Messages/chat.db")).reason,
            "Messages 데이터"
        )
        XCTAssertEqual(
            policy.decision(for: home.appending(path: "Pictures/Photos Library.photoslibrary/originals")).reason,
            "사진 보관함"
        )
        XCTAssertEqual(
            policy.decision(for: home.appending(path: ".ssh/id_ed25519")).reason,
            "SSH 자격증명"
        )
        XCTAssertEqual(
            policy.decision(for: home.appending(path: ".aws/credentials")).reason,
            "AWS 자격증명"
        )
    }
}
