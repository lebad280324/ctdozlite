import XCTest
@testable import CTDoNative

final class ComposerLayoutTests: XCTestCase {
    @MainActor func testWrappedDraftGrowsWithoutAnExplicitNewline() {
        let text = "Nội dung đang soạn cần xuống dòng đầy đủ trong cửa sổ chat hẹp."
        XCTAssertGreaterThan(NativeComposer.height(for: text, width: 160), NativeComposer.height(for: text, width: 600))
        XCTAssertGreaterThan(NativeComposer.height(for: text, width: 160), 34)
    }

    @MainActor func testLongDraftStopsGrowingAndEmptyDraftStaysCompact() {
        XCTAssertEqual(NativeComposer.height(for: "", width: 160), 34)
        XCTAssertEqual(NativeComposer.height(for: String(repeating: "tin nhắn ", count: 1000), width: 160), 120)
    }
}
