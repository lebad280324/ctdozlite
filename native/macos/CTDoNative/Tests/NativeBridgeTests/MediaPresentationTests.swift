import XCTest
@testable import NativeBridge
final class MediaPresentationTests: XCTestCase {
 func message(_ fields:[String:Any])throws->MessageSnapshot {try JSONDecoder().decode(MessageSnapshot.self,from:JSONSerialization.data(withJSONObject:["id":"one"].merging(fields){_,new in new}))}
 func testPhotoDoesNotRepeatCdnPreviewOrPlaceholder()throws{
  let photo=try message(["text":"[Hình ảnh]","image_url":"https://example.invalid/photo.jpg","link_url":"https://example.invalid/photo.jpg"])
  XCTAssertTrue(MediaPresentation.isBareImage(photo));XCTAssertEqual(MediaPresentation.caption(photo),"");XCTAssertFalse(MediaPresentation.showsLinkPreview(photo))
 }
 func testRealCaptionAndWebLinksRemainVisible()throws{
  let photo=try message(["text":"A real caption","image_url":"https://example.invalid/photo.jpg"])
  XCTAssertEqual(MediaPresentation.caption(photo),"A real caption");XCTAssertFalse(MediaPresentation.isBareImage(photo))
  let link=try message(["text":"Read this","link_url":"https://example.invalid/article"])
  XCTAssertTrue(MediaPresentation.showsLinkPreview(link));XCTAssertEqual(MediaPresentation.caption(link),"Read this")
 }
 func testFilePlaceholderIsNotRepeatedUnderTheCard()throws{
  let file=try message(["text":"[Tập tin] Mo_ta.docx","file_url":"https://example.invalid/f","file_name":"Mo_ta.docx"])
  XCTAssertEqual(MediaPresentation.caption(file),"")
  let linked=try message(["text":"[Tập tin] 2aObo","link_url":"https://video-stal.example.dlfl.vn/2aObo","link_title":"2aObo"])
  XCTAssertEqual(MediaPresentation.caption(linked),"")
  let captioned=try message(["text":"Gửi chị bản sửa","file_url":"https://example.invalid/f","file_name":"Mo_ta.docx"])
  XCTAssertEqual(MediaPresentation.caption(captioned),"Gửi chị bản sửa")
 }
 func testImageFileNamePlaceholderShowsBareImage()throws{
  let shot=try message(["text":"[Hình ảnh] Ảnh màn hình 2026-11-12 lúc 10.55.08.png","image_url":"https://example.invalid/p.jpg"])
  XCTAssertEqual(MediaPresentation.caption(shot),"");XCTAssertTrue(MediaPresentation.isBareImage(shot))
  let captioned=try message(["text":"[Hình ảnh] xem giúp em","image_url":"https://example.invalid/p.jpg"])
  XCTAssertEqual(MediaPresentation.caption(captioned),"[Hình ảnh] xem giúp em")
 }
 func testSentFileWithSizeInNameShowsCardOnly()throws{
  let sent=try message(["text":"[Tập tin] Ban_tong_ket.docx","file_url":"https://example.invalid/f","file_name":"Ban_tong_ket.docx (40.0 KB)","is_outgoing":true])
  XCTAssertEqual(MediaPresentation.caption(sent),"");XCTAssertEqual(MediaPresentation.fileName(sent),"Ban_tong_ket.docx")
  let odd=try message(["text":"x","file_url":"https://example.invalid/f","file_name":"Bao cao (ban cuoi)"])
  XCTAssertEqual(MediaPresentation.fileName(odd),"Bao cao (ban cuoi)")
 }
}
