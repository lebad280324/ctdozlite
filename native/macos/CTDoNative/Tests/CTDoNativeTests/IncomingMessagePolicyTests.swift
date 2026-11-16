import XCTest
import NativeBridge
@testable import CTDoNative

final class IncomingMessagePolicyTests: XCTestCase {
    private func thread(_ extra: String = "") throws -> ThreadSnapshot {
        try JSONDecoder().decode(ThreadSnapshot.self, from: Data("{\"id\":\"one\",\"unread\":2\(extra)}".utf8))
    }

    func testStartupDuplicatesMutedHiddenAndForegroundReadingDoNotNotify() throws {
        let value = try thread()
        XCTAssertTrue(IncomingMessagePolicy.candidates([value],previousUnread:[:],hadSnapshot:false,readingThreadID:nil).isEmpty)
        XCTAssertTrue(IncomingMessagePolicy.candidates([value],previousUnread:["one":2],hadSnapshot:true,readingThreadID:nil).isEmpty)
        XCTAssertTrue(IncomingMessagePolicy.candidates([value],previousUnread:[:],hadSnapshot:true,readingThreadID:"one").isEmpty)
        for flag in [",\"muted\":true",",\"hidden\":true"] {
            XCTAssertTrue(IncomingMessagePolicy.candidates([try thread(flag)],previousUnread:[:],hadSnapshot:true,readingThreadID:nil).isEmpty)
        }
    }

    func testNewIncomingNotifiesInBackgroundAndOtherConversations() throws {
        let value = try thread()
        for reading in [nil,"another"] as [String?] {
            XCTAssertEqual(IncomingMessagePolicy.candidates([value],previousUnread:["one":1],hadSnapshot:true,readingThreadID:reading).map(\.id),["one"])
        }
    }

    func testManualUnreadMarkShowsBadgeWithoutGeneratingANewMessageNotification() throws {
        let value = try JSONDecoder().decode(ThreadSnapshot.self,from:Data("{\"id\":\"one\",\"marked_unread\":true}".utf8))
        XCTAssertTrue(value.hasUnread)
        XCTAssertEqual(value.unread,0)
        XCTAssertTrue(IncomingMessagePolicy.candidates([value],previousUnread:[:],hadSnapshot:true,readingThreadID:nil).isEmpty)
        let old = try JSONDecoder().decode(ThreadSnapshot.self,from:Data("{\"id\":\"legacy\"}".utf8))
        XCTAssertFalse(old.hasUnread)
    }
}
