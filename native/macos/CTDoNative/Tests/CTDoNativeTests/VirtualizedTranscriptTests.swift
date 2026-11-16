import XCTest
import SwiftUI
import NativeBridge
@testable import CTDoNative

final class VirtualizedTranscriptTests: XCTestCase {
    @MainActor func testFirstViewportAndResizeDoNotMeasureTheWholeHistoryWindow() throws {
        let fixture = try Fixture(count:400)
        fixture.coordinator.update(fixture.parent)
        assertVisibleHeights(fixture)
        XCTAssertLessThan(fixture.exactHeightCount,40)
        fixture.scroll.setFrameSize(NSSize(width:420,height:300))
        fixture.scroll.tile()
        fixture.coordinator.update(fixture.parent)
        assertVisibleHeights(fixture)
        XCTAssertLessThan(fixture.exactHeightCount,40)
        XCTAssertTrue(try XCTUnwrap(fixture.coordinator.anchor()).bottom)
    }

    @MainActor func testScrollingIntoUnpreparedRowsPreservesTheReadingAnchor() throws {
        let fixture = try Fixture(count:400)
        fixture.coordinator.update(fixture.parent)
        fixture.scroll.contentView.scroll(to:NSPoint(x:0,y:fixture.table.rect(ofRow:150).minY+7))
        let before = try XCTUnwrap(fixture.coordinator.anchor())
        fixture.coordinator.flushScroll()
        let after = try XCTUnwrap(fixture.coordinator.anchor())
        XCTAssertEqual(after.messageID,before.messageID)
        XCTAssertEqual(after.offset,before.offset,accuracy:1)
        assertVisibleHeights(fixture)
        fixture.coordinator.savePosition()
        fixture.scroll.setFrameSize(NSSize(width:420,height:300))
        fixture.scroll.tile()
        fixture.coordinator.update(fixture.parent)
        let resized = try XCTUnwrap(fixture.coordinator.anchor())
        XCTAssertEqual(resized.messageID,before.messageID)
        XCTAssertEqual(resized.offset,before.offset,accuracy:1)
        assertVisibleHeights(fixture)
    }

    @MainActor func testNewThreadUsesItsOwnPositionInsteadOfThePreviousThreadsAnchor() throws {
        let fixture = try Fixture(count:100)
        fixture.coordinator.update(fixture.parent)
        fixture.scroll.contentView.scroll(to:NSPoint(x:0,y:fixture.table.rect(ofRow:15).minY+7))
        fixture.coordinator.savePosition()
        XCTAssertFalse(try XCTUnwrap(fixture.coordinator.anchor()).bottom)
        fixture.model.activate("two",messages:try messages(count:100,prefix:"second"))
        let second = NativeTranscript(model:fixture.model,threadID:"two",rows:fixture.model.rows,jump:nil,configuration:0,
            content:{_ in AnyView(ResponsiveContent())},loadMore:{},loadNewer:{},bottomChanged:{_ in})
        fixture.coordinator.update(second)
        XCTAssertTrue(try XCTUnwrap(fixture.coordinator.anchor()).bottom)
        fixture.model.activate("one",messages:try messages(count:100,prefix:"first"))
        fixture.coordinator.update(fixture.parent)
        let restored = try XCTUnwrap(fixture.coordinator.anchor())
        XCTAssertEqual(restored.messageID,"first-15")
        XCTAssertEqual(restored.offset,7,accuracy:1)
    }

    @MainActor func testDeferredPreparationCompletesAtTheLatestWidthWithoutMovingTheAnchor() async throws {
        let fixture = try Fixture(count:100)
        let window = NSWindow(contentRect:fixture.scroll.frame,styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        window.contentView = fixture.scroll
        defer {fixture.coordinator.cancelPreparation();window.contentView = nil;window.close()}
        fixture.coordinator.update(fixture.parent)
        fixture.scroll.contentView.scroll(to:NSPoint(x:0,y:fixture.table.rect(ofRow:40).minY+7))
        fixture.coordinator.flushScroll()
        let before = try XCTUnwrap(fixture.coordinator.anchor())
        try await Task.sleep(nanoseconds:40_000_000)
        fixture.scroll.setFrameSize(NSSize(width:420,height:300))
        fixture.scroll.tile()
        fixture.coordinator.update(fixture.parent)
        for _ in 0..<100 {
            if fixture.exactHeightCount == 100 {break}
            try await Task.sleep(nanoseconds:20_000_000)
        }
        XCTAssertEqual(fixture.exactHeightCount,100)
        let after = try XCTUnwrap(fixture.coordinator.anchor())
        XCTAssertEqual(after.messageID,before.messageID)
        XCTAssertEqual(after.offset,before.offset,accuracy:1)
        assertVisibleHeights(fixture)
    }

    @MainActor private func assertVisibleHeights(_ fixture:Fixture,file:StaticString=#filePath,line:UInt=#line) {
        let range = fixture.table.rows(in:fixture.scroll.contentView.bounds)
        XCTAssertNotEqual(range.location,NSNotFound,file:file,line:line)
        guard range.location != NSNotFound else{return}
        for index in range.location..<range.location+range.length {
            let exact = fixture.model.height(for:fixture.coordinator.displayed[index],width:fixture.coordinator.width)
            XCTAssertNotNil(exact,file:file,line:line)
            XCTAssertEqual(fixture.table.rect(ofRow:index).height,exact ?? 0,accuracy:1,file:file,line:line)
        }
    }

    private struct ResponsiveContent:View {
        @Environment(\.transcriptColumnWidth) var width
        var body:some View {Text("Synthetic message").frame(height:width < 500 ? 90 : 44)}
    }

    @MainActor private final class Fixture {
        let model = TranscriptModel()
        let scroll = TranscriptScrollView(frame:NSRect(x:0,y:0,width:600,height:300))
        let table = NSTableView(frame:.zero)
        let parent:NativeTranscript
        let coordinator:NativeTranscript.Coordinator
        var exactHeightCount:Int {coordinator.displayed.filter{model.height(for:$0,width:coordinator.width) != nil}.count}

        init(count:Int) throws {
            _ = NSApplication.shared
            model.activate("one",messages:try messages(count:count,prefix:"first"))
            parent = NativeTranscript(model:model,threadID:"one",rows:model.rows,jump:nil,configuration:0,
                content:{_ in AnyView(ResponsiveContent())},loadMore:{},loadNewer:{},bottomChanged:{_ in})
            coordinator = NativeTranscript.Coordinator(parent)
            table.style = .fullWidth
            table.intercellSpacing = .zero
            table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
            table.headerView = nil
            table.addTableColumn(NSTableColumn(identifier:.init("message")))
            table.delegate = coordinator
            table.dataSource = coordinator
            scroll.documentView = table
            coordinator.table = table
            coordinator.scroll = scroll
        }
    }
}

private func messages(count:Int,prefix:String) throws -> [MessageSnapshot] {
    let data = try JSONSerialization.data(withJSONObject:(0..<count).map {
        ["id":"\(prefix)-\($0)","timestamp":$0*1000,"text":"Synthetic message \($0)"]
    })
    return try JSONDecoder().decode([MessageSnapshot].self,from:data)
}
