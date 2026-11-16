import XCTest
import SwiftUI
@testable import CTDoNative

final class ConversationColumnLayoutTests:XCTestCase {
    func testSidebarCannotForceTheConversationOutsideANarrowWindow() {
        for width:CGFloat in [760,800,1000] {
            let sidebar=ConversationRegions.sidebarWidth(preferred:380,available:width)
            XCTAssertGreaterThanOrEqual(width-sidebar-24,360)
        }
    }
}
