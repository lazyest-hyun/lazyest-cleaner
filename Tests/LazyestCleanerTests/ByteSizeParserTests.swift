import XCTest
@testable import LazyestCleaner

final class ByteSizeParserTests: XCTestCase {
    func testParsesDecimalAndBinaryUnits() {
        XCTAssertEqual(ByteSizeParser.parse("1.5GB"), 1_500_000_000)
        XCTAssertEqual(ByteSizeParser.parse("2 GiB"), 2_147_483_648)
        XCTAssertEqual(ByteSizeParser.parse("812MB (73%)"), 812_000_000)
        XCTAssertEqual(ByteSizeParser.parse("1,024 B"), 1_024)
    }

    func testRejectsMissingOrUnknownUnits() {
        XCTAssertNil(ByteSizeParser.parse(""))
        XCTAssertNil(ByteSizeParser.parse("42"))
        XCTAssertNil(ByteSizeParser.parse("12 widgets"))
    }
}
