import XCTest
@testable import CTDoNative

final class MessageTypographyTests: XCTestCase {
    func testInlineFormattingPreservesVietnameseEmojiAndSurroundingText() {
        let value=MessageTypography.inline("Gửi **chào bạn 👋** và __lời nhắn__.")
        XCTAssertEqual(String(value.characters),"Gửi chào bạn 👋 và lời nhắn.")
        XCTAssertTrue(value.runs.contains{$0.font != nil})
        XCTAssertTrue(value.runs.contains{$0.underlineStyle != nil})
    }
    func testUnmatchedMarkersKeepTheirOriginalText() {
        XCTAssertEqual(String(MessageTypography.inline("Giá 2 và **chưa đóng").characters),"Giá 2 và **chưa đóng")
    }
}
