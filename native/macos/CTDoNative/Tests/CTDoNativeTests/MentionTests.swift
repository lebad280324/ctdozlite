import XCTest
@testable import CTDoNative

final class MentionTests: XCTestCase {
    func testTaggedNamesAreRecognisedButEmailsAreNot() {
        XCTAssertTrue(MessageTypography.hasMention("Đề nghị @Lê Bá quay lại tắt quạt"))
        XCTAssertTrue(MessageTypography.hasMention("@All tất cả các bạn"))
        XCTAssertFalse(MessageTypography.hasMention("gửi vào it@anphat.vn nhé"))
        XCTAssertFalse(MessageTypography.hasMention("giá @ 20k"))
    }
    func testMentionIsStyledApartFromTheRest() {
        let styled = MessageTypography.withMentions("Nhờ @Thu Hương xem", outgoing: false)
        let tagged = styled.runs.filter { $0.foregroundColor != nil }.map { String(styled[$0.range].characters) }
        XCTAssertEqual(tagged, ["@Thu Hương"])
    }
}
