import XCTest
import SwiftUI
import NativeBridge
@testable import CTDoNative

private struct RegionProbe:NSViewRepresentable {
    let id:String
    let color:NSColor
    func makeNSView(context:Context)->NSView {
        let view=NSView();view.identifier=NSUserInterfaceItemIdentifier(id)
        view.wantsLayer=true;view.layer?.backgroundColor=color.cgColor
        return view
    }
    func updateNSView(_ view:NSView,context:Context) {}
}

final class ConversationViewportTests:XCTestCase {
    @MainActor func testHistoryFillsColumnBehindFloatingControlsWithReadableEndpoints() async throws {
        _=NSApplication.shared
        let messages=try JSONDecoder().decode([MessageSnapshot].self,from:JSONSerialization.data(withJSONObject:(0..<30).map{["id":"m-\($0)","text":"Nội dung thử nghiệm \($0)","timestamp":$0*1000]}))
        let model=TranscriptModel();model.activate("test",messages:messages)
        let root=ConversationViewport { top, bottom in
            NativeTranscript(model:model,threadID:"test",rows:model.rows,jump:nil,configuration:0,
                topInset:top,bottomInset:bottom,
                content:{AnyView(Text($0.message.text).frame(height:44))},loadMore:{},loadNewer:{},bottomChanged:{_ in})
        } header: {
            VStack(spacing:0) {
                RegionProbe(id:"header",color:.systemGreen).frame(height:76)
                RegionProbe(id:"controls",color:.systemOrange).frame(height:28)
            }
        } composer: {
            RegionProbe(id:"composer",color:.systemBlue).frame(height:120)
        }
        let host=NSHostingController(rootView:root);host.sizingOptions=[];host.safeAreaRegions=[]
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:600,height:540),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=host.view
        defer {window.contentView=nil;window.close()}
        host.view.frame=NSRect(x:0,y:0,width:600,height:540);host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds:20_000_000)
        host.view.layoutSubtreeIfNeeded()
        func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap(descendants)}
        let views=descendants(host.view)
        let history=try XCTUnwrap(views.first{$0 is TranscriptScrollView})
        let header=try XCTUnwrap(views.first{$0.identifier?.rawValue=="header"})
        let controls=try XCTUnwrap(views.first{$0.identifier?.rawValue=="controls"})
        let composer=try XCTUnwrap(views.first{$0.identifier?.rawValue=="composer"})
        let rect=history.convert(history.bounds,to:host.view)
        XCTAssertEqual(rect.width,600,accuracy:1)
        XCTAssertEqual(rect.height,540,accuracy:1)
        let scroll=try XCTUnwrap(history as? TranscriptScrollView)
        XCTAssertEqual(scroll.contentInsets.top,104,accuracy:1)
        XCTAssertEqual(scroll.contentInsets.bottom,120,accuracy:1)
        for item in [header,controls,composer] {
            XCTAssertTrue(rect.contains(item.convert(item.bounds,to:host.view)),"Floating controls must overlay the full history viewport")
        }
        if let directory=ProcessInfo.processInfo.environment["CTDOZLITE_TEST_RENDER_DIRECTORY"],
           let bitmap=host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds) {
            host.view.cacheDisplay(in:host.view.bounds,to:bitmap)
            if let png=bitmap.representation(using:.png,properties:[:]) {
                try await Task.detached {
                    let url=URL(fileURLWithPath:directory,isDirectory:true)
                    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
                    try png.write(to:url.appendingPathComponent("conversation-regions.png"))
                }.value
            }
        }
    }
}
