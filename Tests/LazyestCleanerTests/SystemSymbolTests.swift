import AppKit
import XCTest
@testable import LazyestCleaner

final class SystemSymbolTests: XCTestCase {
    func testEveryCataloguedSymbolExistsOnMinimumSupportedMacOS() {
        let symbols = Set(
            CleanupActionID.allCases.map { ActionCatalog.descriptor(for: $0).systemImage }
                + CleanupCategory.allCases.map(\.symbol)
                + CleanupWorkspace.allCases.map(\.symbol)
                + CleanupItemKind.allCases.map(\.symbol)
                + CleanupRisk.allCases.map(\.symbol)
                + CleanupScanIssueKind.allCases.map(\.symbol)
                + Self.staticViewSymbols
        )

        for symbol in symbols.sorted() {
            XCTAssertNotNil(
                NSImage(systemSymbolName: symbol, accessibilityDescription: nil),
                "Missing SF Symbol: \(symbol)"
            )
        }
    }

    private static let staticViewSymbols = [
        "app",
        "app.badge.checkmark",
        "arrow.up.arrow.down",
        "checkmark.circle.fill",
        "chevron.right",
        "doc.on.doc",
        "ellipsis.circle",
        "externaldrive.badge.timemachine",
        "internaldrive",
        "line.3.horizontal.decrease",
        "lock.fill",
        "lock.shield",
        "minus",
        "plus",
        "xmark",
    ]
}
