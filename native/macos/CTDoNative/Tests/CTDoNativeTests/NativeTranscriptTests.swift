import XCTest
import SwiftUI
import NativeBridge
@testable import CTDoNative

final class NativeTranscriptTests:XCTestCase {
    @MainActor func testViewportSizingStaysBoundedByTheProposedWindow() {
        XCTAssertEqual(NativeTranscript.viewportSize(.init(width:600,height:500),fallback:.zero),CGSize(width:600,height:500))
        XCTAssertEqual(NativeTranscript.viewportSize(.unspecified,fallback:CGSize(width:600,height:500)),CGSize(width:600,height:500))
        XCTAssertEqual(NativeTranscript.viewportSize(.init(width:.infinity,height:.infinity),fallback:CGSize(width:600,height:500)),CGSize(width:600,height:500))
        let scroll=TranscriptScrollView(frame:NSRect(x:0,y:0,width:600,height:500))
        scroll.documentView=NSView(frame:NSRect(x:0,y:0,width:600,height:80_000))
        XCTAssertEqual(scroll.fittingSize,.zero)
        XCTAssertEqual(scroll.intrinsicContentSize,NSSize(width:NSView.noIntrinsicMetric,height:NSView.noIntrinsicMetric))
    }

    @MainActor func testReusedCellMeasuresContentWithoutInstallingContentSizeConstraints() {
        _=NSApplication.shared
        let cell=TranscriptCell()
        for i in 0..<40 {
            let height=cell.configure(AnyView(Text("Synthetic message \(i)").frame(height:44)),width:500)
            XCTAssertEqual(height,46,accuracy:1)
            XCTAssertEqual(cell.subviews[0].frame.width,500,accuracy:1)
            XCTAssertEqual(cell.subviews[0].frame.height,height,accuracy:1)
            cell.frame=NSRect(x:0,y:0,width:500,height:height);cell.layoutSubtreeIfNeeded()
            XCTAssertEqual(cell.subviews.count,1)
            XCTAssertTrue(cell.subviews[0].constraints.isEmpty)
            cell.setFrameSize(NSSize(width:320,height:height))
            XCTAssertEqual(cell.subviews[0].frame.width,320,accuracy:1)
        }
    }

    @MainActor func testMessageWrapsWhenTheTranscriptNarrows() async throws {
        _=NSApplication.shared
        let data=try JSONSerialization.data(withJSONObject:["id":"example","text":String(repeating:"Nội dung thử nghiệm co giãn theo cửa sổ. ",count:8),"timestamp":1000,"is_outgoing":true])
        let message=try JSONDecoder().decode(MessageSnapshot.self,from:data)
        let cell=TranscriptCell()
        let content=AnyView(MessageRow(message:message,showSender:false,onQuoteJump:{_ in}))
        let wide=cell.configure(content,width:700)
        let widePNG=renderIfRequested(cell,width:700,height:wide)
        let narrow=cell.configure(content,width:320)
        let narrowPNG=renderIfRequested(cell,width:320,height:narrow)
        XCTAssertGreaterThan(narrow,wide)
        XCTAssertEqual(cell.subviews[0].frame.width,320,accuracy:1)
        XCTAssertEqual(cell.subviews[0].frame.height,narrow,accuracy:1)
        if let directory=ProcessInfo.processInfo.environment["CTDOZLITE_TEST_RENDER_DIRECTORY"] {
            try await Task.detached {
                let url=URL(fileURLWithPath:directory,isDirectory:true)
                try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
                if let widePNG {try widePNG.write(to:url.appendingPathComponent("message-wide.png"))}
                if let narrowPNG {try narrowPNG.write(to:url.appendingPathComponent("message-narrow.png"))}
            }.value
        }
    }

    @MainActor private func renderIfRequested(_ cell:TranscriptCell,width:CGFloat,height:CGFloat)->Data? {
        guard ProcessInfo.processInfo.environment["CTDOZLITE_TEST_RENDER_DIRECTORY"] != nil else{return nil}
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        defer {window.contentView=nil;window.close()}
        let content=NSView(frame:NSRect(x:0,y:0,width:width,height:height))
        content.wantsLayer=true;content.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor
        window.contentView=content
        cell.setFrameSize(NSSize(width:width,height:height));content.addSubview(cell);content.layoutSubtreeIfNeeded()
        guard let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds) else{return nil}
        content.cacheDisplay(in:content.bounds,to:bitmap)
        return bitmap.representation(using:.png,properties:[:])
    }

    @MainActor func testInitialRowsWaitForViewportAndFollowOnePointWidthChanges() throws {
        _=NSApplication.shared
        let model=TranscriptModel(),items=try rows(0..<5)
        let parent=NativeTranscript(model:model,threadID:"one",rows:items,jump:nil,configuration:0,content:{AnyView(Text($0.message.text))},loadMore:{},loadNewer:{},bottomChanged:{_ in})
        let coordinator=NativeTranscript.Coordinator(parent)
        let scroll=TranscriptScrollView(frame:.zero),table=NSTableView(frame:.zero)
        table.style = .fullWidth;table.intercellSpacing = .zero;table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle;table.headerView=nil
        table.addTableColumn(NSTableColumn(identifier:.init("message")));table.delegate=coordinator;table.dataSource=coordinator
        scroll.documentView=table;coordinator.table=table;coordinator.scroll=scroll
        coordinator.update(parent)
        XCTAssertTrue(coordinator.displayed.isEmpty,"An unlaid-out viewport must not commit narrow provisional rows")
        scroll.setFrameSize(NSSize(width:600,height:500));scroll.tile();coordinator.update(parent)
        let width=coordinator.width
        XCTAssertEqual(coordinator.displayed.count,5)
        scroll.setFrameSize(NSSize(width:599,height:500));scroll.tile();coordinator.update(parent)
        XCTAssertEqual(coordinator.width,width-1,accuracy:0.01)
        XCTAssertEqual(table.frame.width,scroll.contentView.bounds.width,accuracy:0.01)
    }

    @MainActor func testComposerGrowthPreservesBottomOrTheCurrentReadingAnchor() throws {
        _=NSApplication.shared
        let model=TranscriptModel(),items=try rows(0..<50)
        model.activate("one",messages:items.map(\.message))
        let parent=NativeTranscript(model:model,threadID:"one",rows:items,jump:nil,configuration:0,content:{AnyView(Text($0.message.text).frame(height:44))},loadMore:{},loadNewer:{},bottomChanged:{_ in})
        let coordinator=NativeTranscript.Coordinator(parent)
        let scroll=TranscriptScrollView(frame:NSRect(x:0,y:0,width:600,height:500)),table=NSTableView(frame:.zero)
        table.style = .fullWidth;table.intercellSpacing = .zero;table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView=nil;table.addTableColumn(NSTableColumn(identifier:.init("message")));table.delegate=coordinator;table.dataSource=coordinator
        scroll.documentView=table;coordinator.table=table;coordinator.scroll=scroll
        coordinator.update(parent);XCTAssertTrue(try XCTUnwrap(coordinator.anchor()).bottom)
        scroll.setFrameSize(NSSize(width:600,height:380));scroll.tile();coordinator.update(parent)
        XCTAssertTrue(try XCTUnwrap(coordinator.anchor()).bottom)
        scroll.contentView.scroll(to:NSPoint(x:0,y:table.rect(ofRow:15).minY+7));coordinator.savePosition()
        let before=try XCTUnwrap(coordinator.anchor())
        scroll.setFrameSize(NSSize(width:600,height:280));scroll.tile();coordinator.update(parent)
        let after=try XCTUnwrap(coordinator.anchor())
        XCTAssertEqual(after.messageID,before.messageID);XCTAssertEqual(after.offset,before.offset,accuracy:1)
    }

    private func rows(_ range:Range<Int>) throws -> [TranscriptRow] {
        let data=try JSONSerialization.data(withJSONObject:range.map{["id":"m-\($0)","timestamp":$0*1000,"text":"Synthetic message \($0)"]})
        return TranscriptLayout.rows(try JSONDecoder().decode([MessageSnapshot].self,from:data))
    }
    @MainActor func testPrependingHistoryKeepsTheSameMessageAtTheSameOffset() throws {
        _=NSApplication.shared
        let model=TranscriptModel()
        let initial=try rows(50..<100)
        func view(_ rows:[TranscriptRow])->NativeTranscript {
            NativeTranscript(model:model,threadID:"one",rows:rows,jump:nil,configuration:0,content:{AnyView(Text($0.message.text).frame(height:44))},loadMore:{},loadNewer:{},bottomChanged:{_ in})
        }
        let parent=view(initial),coordinator=NativeTranscript.Coordinator(parent)
        let scroll=TranscriptScrollView(frame:NSRect(x:0,y:0,width:600,height:500)),table=NSTableView(frame:NSRect(x:0,y:0,width:600,height:0))
        table.style = .fullWidth;table.intercellSpacing = .zero;table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView=nil;table.addTableColumn(NSTableColumn(identifier:.init("message")));table.delegate=coordinator;table.dataSource=coordinator
        scroll.documentView=table;coordinator.table=table;coordinator.scroll=scroll
        coordinator.update(parent)
        let visible=table.rows(in:scroll.contentView.bounds)
        XCTAssertTrue((visible.location..<visible.location+visible.length).allSatisfy{model.height(for:initial[$0],width:coordinator.width) != nil},"Visible rows must have exact heights before presentation")
        XCTAssertLessThan(initial.filter{model.height(for:$0,width:coordinator.width) != nil}.count,initial.count,"The first viewport must not fit the whole loaded page")
        _=coordinator.tableView(table,viewFor:table.tableColumns[0],row:0)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(model.height(for:initial[0],width:coordinator.width)),46,"A 44-point hosting view must not collapse to the minimum row height")
        scroll.contentView.scroll(to:NSPoint(x:0,y:table.rect(ofRow:15).minY+7))
        let before=try XCTUnwrap(coordinator.anchor())
        XCTAssertFalse(before.bottom)
        coordinator.update(view(try rows(0..<100)))
        let after=try XCTUnwrap(coordinator.anchor())
        XCTAssertEqual(after.messageID,before.messageID)
        XCTAssertEqual(after.offset,before.offset,accuracy:1)
        XCTAssertEqual(table.numberOfRows,100)
    }
}
