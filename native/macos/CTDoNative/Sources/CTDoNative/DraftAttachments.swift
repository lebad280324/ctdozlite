import SwiftUI
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct DraftAttachments: View {
 @EnvironmentObject var store:AppStore
 var body:some View {
  ScrollView(.horizontal,showsIndicators:false){HStack(spacing:10){ForEach(store.pendingAttachments,id:\.self){url in
   DraftAttachmentCard(url:url){withAnimation(.snappy(duration:0.2)){store.removeAttachment(url)}}
  }}.padding(.vertical,3)}.frame(height:104)
 }
}
private struct DraftAttachmentCard: View {
 let url:URL
 let remove:()->Void
 @State private var image:NSImage?
 @State private var detail=""
 @State private var request:QLThumbnailGenerator.Request?
 private var isImage:Bool {UTType(filenameExtension:url.pathExtension)?.conforms(to:.image)==true}
 var body:some View {
  Group {
   if isImage { preview.frame(width:116,height:94).background(Color.primary.opacity(0.04)) }
   else {HStack(spacing:10){preview.frame(width:64,height:72);VStack(alignment:.leading,spacing:4){Text(verbatim:url.lastPathComponent).font(.callout.weight(.semibold)).lineLimit(2);Text(UTType(filenameExtension:url.pathExtension)?.localizedDescription ?? "Tệp đính kèm").font(.caption).foregroundStyle(.secondary).lineLimit(1);Text(verbatim:detail).font(.caption).foregroundStyle(.secondary)}}.padding(10).frame(width:238,height:94).background(Color.primary.opacity(0.045))}
  }.clipShape(RoundedRectangle(cornerRadius:14))
   .overlay(alignment:.topTrailing){Button(action:remove){Image(systemName:"xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.secondary,Color(nsColor:.controlBackgroundColor)).font(.system(size:17))}.buttonStyle(.plain).padding(5).help("Bỏ tệp đính kèm")}
   .accessibilityLabel(isImage ? "Ảnh đính kèm" : url.lastPathComponent)
   .task(id:url){
    let request=QLThumbnailGenerator.Request(fileAt:url,size:NSSize(width:116,height:94),scale:2,representationTypes:.all);self.request=request
    QLThumbnailGenerator.shared.generateBestRepresentation(for:request){result,_ in
     guard let result else{return};Task{@MainActor in self.image=result.nsImage}
    }
    let size=await Task.detached{(try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0}.value
    detail=ByteCountFormatter.string(fromByteCount:Int64(size),countStyle:.file)
   }.onDisappear{if let request {QLThumbnailGenerator.shared.cancel(request)}}
 }
 @ViewBuilder private var preview:some View {
  if let image {Image(nsImage:image).resizable().scaledToFit().padding(isImage ? 0 : 3)}
  else {Image(systemName:isImage ? "photo" : "doc.fill").font(.system(size:28)).foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)}
 }
}

struct LivelyButtonStyle: ButtonStyle {
 @Environment(\.accessibilityReduceMotion) private var reduced
 func makeBody(configuration:Configuration)->some View {
  configuration.label.scaleEffect(configuration.isPressed ? 0.91 : 1).opacity(configuration.isPressed ? 0.75 : 1)
   .animation(reduced ? nil : .spring(response:0.2,dampingFraction:0.7),value:configuration.isPressed)
 }
}
