import XCTest
@testable import CTDoNative

final class RecentSearchHistoryTests: XCTestCase {
    @MainActor func testRecentSearchesAreBoundedDeduplicatedAndNewestFirst() throws {
        let history = RecentSearchHistory()
        history.activate(account:"",persistent:false)
        history.remember("   ")
        XCTAssertTrue(history.queries.isEmpty)
        for n in 0..<14 { history.remember("Tìm \(n)") }
        XCTAssertEqual(history.queries.count,12)
        history.remember("  tìm 5\n")
        XCTAssertEqual(history.queries.first,"tìm 5")
        XCTAssertEqual(history.queries.count,12)
        XCTAssertFalse(history.queries.contains("Tìm 5"))
        history.remove("tìm 5")
        XCTAssertFalse(history.queries.contains("tìm 5"))
        history.clear()
        XCTAssertTrue(history.queries.isEmpty)
    }

    @MainActor func testHistoryPersistsSeparatelyForEachAccountAndDemoDoesNotWrite() throws {
        let suite = "ctdo-search-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let history = RecentSearchHistory(defaults:defaults)
        history.activate(account:"account-a",persistent:true)
        history.remember("Dự án A")
        history.activate(account:"account-b",persistent:true)
        XCTAssertTrue(history.queries.isEmpty)
        history.remember("Dự án B")
        let reopened = RecentSearchHistory(defaults:defaults)
        reopened.activate(account:"account-a",persistent:true)
        XCTAssertEqual(reopened.queries,["Dự án A"])
        reopened.clear()
        reopened.activate(account:"account-b",persistent:true)
        XCTAssertEqual(reopened.queries,["Dự án B"])
        reopened.activate(account:"account-b",persistent:false)
        reopened.remember("Minh họa")
        reopened.activate(account:"account-b",persistent:true)
        XCTAssertEqual(reopened.queries,["Dự án B"])
    }
}
