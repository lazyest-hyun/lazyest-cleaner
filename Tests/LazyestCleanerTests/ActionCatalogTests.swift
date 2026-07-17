import XCTest
@testable import LazyestCleaner

final class ActionCatalogTests: XCTestCase {
    func testEveryActionHasOneCompleteDescriptor() {
        let descriptors = CleanupActionID.allCases.map(ActionCatalog.descriptor)

        XCTAssertEqual(Set(descriptors.map(\.id)).count, CleanupActionID.allCases.count)
        XCTAssertTrue(descriptors.allSatisfy { !$0.title.isEmpty })
        XCTAssertTrue(descriptors.allSatisfy { !$0.systemImage.isEmpty })
        XCTAssertTrue(descriptors.allSatisfy { !$0.tooltip.isEmpty })
    }

    func testDestructiveActionsAlwaysRequireConfirmation() {
        let destructiveDescriptors = CleanupActionID.allCases
            .map(ActionCatalog.descriptor)
            .filter { $0.role == .destructive }
        XCTAssertTrue(destructiveDescriptors.allSatisfy { $0.confirmation != .none })

        for action in [
            CleanupActionID.removeImmediately,
            .removeAppData,
            .uninstallApplication,
            .deletePermanently,
            .runDockerCleanup,
        ] {
            let descriptor = ActionCatalog.descriptor(for: action)
            XCTAssertEqual(descriptor.role, .destructive)
            XCTAssertEqual(descriptor.confirmation, .reinforced)
        }

        XCTAssertEqual(
            ActionCatalog.descriptor(for: .removeApplicationOnly).confirmation,
            .standard
        )
    }

    func testFullDiskAccessActionMakesSystemOwnedGrantExplicit() {
        let descriptor = ActionCatalog.descriptor(for: .openFullDiskAccess)

        XCTAssertEqual(descriptor.title, "설정에서 허용")
        XCTAssertEqual(descriptor.systemImage, "gearshape")
        XCTAssertTrue(descriptor.tooltip.contains("macOS"))
    }
}
