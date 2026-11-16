import XCTest
import SwiftUI
import NativeBridge
@testable import CTDoNative

final class SearchAndReplyFocusTests: XCTestCase {
    @MainActor func testSearchFocusWaitsForWindowAttachment() async throws {
        _ = NSApplication.shared
        let field = TypingSearchField()
        field.stringValue = "Đang tìm"
        field.requestTypingFocus()
        await Task.yield()
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:120),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let content = NSView(frame:NSRect(x:0,y:0,width:400,height:120))
        window.contentView = content
        field.frame = NSRect(x:20,y:20,width:300,height:30)
        content.addSubview(field)
        try await Task.sleep(nanoseconds:30_000_000)
        XCTAssertTrue(window.firstResponder === field.currentEditor())
        XCTAssertNotNil(field.currentEditor())
        XCTAssertEqual(field.stringValue,"Đang tìm")
    }

    @MainActor func testReplyFocusPreservesDraftAndDoesNotRepeatAfterTypingElsewhere() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:200),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let content = NSView(frame:NSRect(x:0,y:0,width:400,height:200))
        window.contentView = content
        let editor = ComposerTextView(frame:NSRect(x:0,y:0,width:300,height:80))
        editor.string = "Bản nháp tiếng Việt"
        editor.setSelectedRange(NSRange(location:4,length:0))
        editor.requestTypingFocus(true)
        content.addSubview(editor)
        let other = NSTextField(frame:NSRect(x:0,y:120,width:300,height:30))
        content.addSubview(other)
        try await Task.sleep(nanoseconds:30_000_000)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.string,"Bản nháp tiếng Việt")
        XCTAssertEqual(editor.selectedRange().location,4)
        window.makeFirstResponder(other)
        editor.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds:20_000_000)
        XCTAssertFalse(window.firstResponder === editor)
        editor.requestTypingFocus(true)
        try await Task.sleep(nanoseconds:20_000_000)
        XCTAssertTrue(window.firstResponder === editor)
    }

    @MainActor func testReplyingAgainToTheSameMessageCreatesAnotherFocusRequest() throws {
        let store = AppStore(arguments:["test","--demo"])
        defer { store.stop() }
        let message = try JSONDecoder().decode(MessageSnapshot.self,from:Data("{\"id\":\"reply-target\"}".utf8))
        let before = store.replyFocusGeneration
        store.quote = message
        store.quote = message
        XCTAssertEqual(store.replyFocusGeneration,before+2)
    }
}
