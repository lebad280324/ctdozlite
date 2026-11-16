import XCTest
import AppKit
@testable import NativeBridge
final class ClipboardFilesTests:XCTestCase {
 func testFileReferencesDecodeEscapedUrlsAndRejectWebLinks(){let rows=ClipboardFiles.urls(from:["file:///tmp/My%20File.txt","/tmp/other.txt","https://example.invalid/file","relative.txt"]);XCTAssertEqual(rows.count,2);XCTAssertEqual(rows[0].lastPathComponent,"My File.txt")}
 @MainActor func testLegacyFinderHistoryRepresentationIsRecognized(){let board=NSPasteboard(name:NSPasteboard.Name("ctdo-legacy-files-"+UUID().uuidString));defer{board.clearContents()};board.clearContents();XCTAssertTrue(board.setPropertyList(["/tmp/first.txt","/tmp/second.txt"],forType:NSPasteboard.PasteboardType("NSFilenamesPboardType")));XCTAssertEqual(ClipboardFiles.read(board).map(\.lastPathComponent),["first.txt","second.txt"])}
}
