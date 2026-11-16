import XCTest
import SwiftUI
import NativeBridge
@testable import CTDoNative

final class TranscriptResizeBenchmark:XCTestCase {
    @MainActor func testTextOnlyWidthChangeCost() throws {
        guard ProcessInfo.processInfo.environment["CTDOZLITE_RESIZE_BENCHMARK"]=="1" else {
            throw XCTSkip("Opt-in component benchmark; does not assert a frame-rate threshold")
        }
        _=NSApplication.shared
        let fixtures=(0..<400).map {i -> [String:Any] in
            var row:[String:Any] = ["id":"resize-\(i)","timestamp":1_790_000_000_000+i*1000,
                "text":String(repeating:"Nội dung thử nghiệm bố trí tin nhắn khi thay đổi chiều rộng. ",count:i%4+1),
                "sender_name":"Người dùng thử","is_outgoing":i%2==0]
            if i%4==0 {row["reply_to_text"]="Nội dung được trả lời trong dữ liệu giả lập";row["reply_to_sender"]="Người gửi thử"}
            return row
        }
        let all=try JSONDecoder().decode([MessageSnapshot].self,from:JSONSerialization.data(withJSONObject:fixtures))
        for count in [20,50,200,400] {
            let model=TranscriptModel();model.activate("resize-test",messages:Array(all.prefix(count)))
            let parent=NativeTranscript(model:model,threadID:"resize-test",rows:model.rows,jump:nil,configuration:0,
                content:{row in AnyView(MessageRow(message:row.message,showSender:row.startsRun,
                    reserveAvatar:!row.message.isOutgoing,senderName:"Người dùng thử",isGroup:true,onQuoteJump:{_ in}).environment(\.colorScheme,.light))},
                loadMore:{},loadNewer:{},bottomChanged:{_ in})
            let coordinator=NativeTranscript.Coordinator(parent)
            let scroll=TranscriptScrollView(frame:NSRect(x:0,y:0,width:740,height:600))
            let table=NSTableView(frame:.zero)
            table.style = .fullWidth;table.intercellSpacing = .zero;table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
            table.headerView=nil;table.addTableColumn(NSTableColumn(identifier:.init("message")))
            table.delegate=coordinator;table.dataSource=coordinator
            scroll.documentView=table;coordinator.table=table;coordinator.scroll=scroll
            coordinator.update(parent)
            var times:[Double]=[]
            for width:CGFloat in [720,700,680,660,640,620] {
                scroll.setFrameSize(NSSize(width:width,height:600));scroll.tile()
                let start=DispatchTime.now().uptimeNanoseconds
                coordinator.update(parent)
                times.append(Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000)
            }
            times.sort()
            let result:[String:Any] = ["task":"current_transcript_width_change","messages":count,"iterations":times.count,
                "min_ms":times.first!,"avg_ms":times.reduce(0,+)/Double(times.count),"p50_ms":times[times.count/2],
                "p95_ms":times.last!,"p99_ms":times.last!,"fixture":"synthetic text and quotes; no network or real account"]
            let data=try JSONSerialization.data(withJSONObject:result,options:.sortedKeys)
            print("RESIZE_COMPONENT_BENCHMARK "+String(data:data,encoding:.utf8)!)
        }
    }
}
