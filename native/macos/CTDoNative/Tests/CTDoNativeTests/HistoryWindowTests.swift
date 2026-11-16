import XCTest
import NativeBridge
@testable import CTDoNative

final class HistoryWindowTests:XCTestCase {
    private func event(_ object:[String:Any]) throws -> CoreEvent {
        var event=try JSONDecoder().decode(CoreEvent.self,from:JSONSerialization.data(withJSONObject:object))
        try event.prepareForUI();return event
    }
    private func row(_ i:Int,text:String?=nil)->[String:Any] {["id":"m-\(i)","timestamp":i*1000,"text":text ?? "Synthetic \(i)"]}
    @MainActor func testOlderWindowStaysPutWhenLiveTailArrivesAndNewerPageClosesGap() throws {
        let store=AppStore(arguments:["test","--demo"]);defer{store.stop()}
        store.selectedThreadID="one"
        store.pageRequests["one"]="old-page"
        store.receive(try event(["id":"old-page","event":"message_page","data":["thread_id":"one","before":["id":"m-450","timestamp":450000],"has_more":true,"messages":(0..<450).map{row($0)}]]))
        XCTAssertEqual(store.selectedMessages.count,400);XCTAssertEqual(store.selectedMessages.first?.id,"m-0")
        XCTAssertTrue(store.historyHasNewer["one"] == true)
        store.receive(try event(["event":"messages","data":["thread_id":"one","messages":[row(900),row(10,text:"Edited")]]]))
        XCTAssertEqual(store.selectedMessages.count,400);XCTAssertEqual(store.selectedMessages.first?.id,"m-0")
        XCTAssertEqual(store.selectedMessages.first(where:{$0.id=="m-10"})?.text,"Edited")
        store.pageRequests["one"]="next-page"
        store.receive(try event(["id":"next-page","event":"message_page","data":["thread_id":"one","after":["id":"m-399","timestamp":399000],"has_more":false,"messages":(400..<450).map{row($0)}]]))
        XCTAssertEqual(store.selectedMessages.count,400);XCTAssertEqual(store.selectedMessages.last?.id,"m-449")
        XCTAssertEqual(store.selectedMessages.first?.id,"m-50");XCTAssertFalse(store.historyHasNewer["one"] ?? true)
    }
    @MainActor func testObsoletePageCannotRepopulateAReopenedOrLoggedOutChat() throws {
        let store=AppStore(arguments:["test","--demo"]);defer{store.stop()}
        store.selectedThreadID="one";store.pageRequests["one"]="new-request"
        store.receive(try event(["id":"obsolete-request","event":"message_page","data":["thread_id":"one","messages":[row(1)]]]))
        XCTAssertTrue(store.selectedMessages.isEmpty)
        store.pageRequests.removeAll()
        store.receive(try event(["id":"new-request","event":"message_page","data":["thread_id":"one","messages":[row(2)]]]))
        XCTAssertTrue(store.selectedMessages.isEmpty)
    }
    @MainActor func testCachedConversationReappearsWithoutWaitingForHistoryResponse() throws {
        let store=AppStore(arguments:["test","--demo"]);defer{store.stop()}
        store.receive(try event(["event":"threads","data":[["id":"one","name":"One"],["id":"two","name":"Two"]]]))
        store.receive(try event(["event":"messages","data":["thread_id":"one","messages":[row(1)]]]))
        store.selectThread("one");store.selectThread("two");store.selectThread("one")
        XCTAssertEqual(store.transcript.rows.first?.id,"m-1")
    }
}
