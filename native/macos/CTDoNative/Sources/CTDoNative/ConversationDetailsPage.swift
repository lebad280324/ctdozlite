import SwiftUI
import NativeBridge

/// A full detail page keeps the sidebar visible and never compresses the transcript.
struct ConversationDetailsPage: View {
    @EnvironmentObject private var store: AppStore
    let thread: ThreadSnapshot
    @State private var showingMore=false
    private var subtitle:String {
        guard thread.isGroup else {return "Cuộc trò chuyện cá nhân"}
        if let count=thread.memberTotal ?? store.features.members[thread.id]?.count,count>0{return "Nhóm · \(count) thành viên"}
        return "Nhóm trò chuyện"
    }
    var body: some View {
        ScrollView {
            VStack(spacing:22) {
                HStack {
                    Button { store.showingInspector=false } label: {Image(systemName:"chevron.left").frame(width:32,height:32)}.buttonStyle(.plain).nativeGlass(16)
                    Spacer()
                    Button { store.showingInspector=false } label: {Image(systemName:"xmark").frame(width:32,height:32)}.buttonStyle(.plain).nativeGlass(16).keyboardShortcut(.cancelAction).help("Đóng thông tin (Esc)")
                }
                VStack(spacing:10) {
                    ThreadAvatar(thread:thread,size:112)
                    Text(verbatim:thread.name).font(.system(size:25,weight:.bold)).multilineTextAlignment(.center).textSelection(.enabled)
                    Text(subtitle).foregroundStyle(.secondary)
                }
                HStack(spacing:12) {
                    if thread.isGroup {tile("person.badge.plus","Thêm"){store.groupToInvite=thread}}
                    else {tile("phone","Gọi"){store.startCall(video:false)}}
                    tile(thread.muted ? "bell":"bell.slash",thread.muted ? "Bật thông báo":"Tắt thông báo"){store.threadCommand("mute_thread",thread:thread,parameters:["mute":.bool(!thread.muted)])}
                    tile("ellipsis","Thêm"){showingMore.toggle()}
                        .popover(isPresented:$showingMore){
                            VStack(alignment:.leading,spacing:14){
                                ThreadContextMenu(thread:thread)
                                Button("Đặt tên gợi nhớ"){showingMore=false;store.aliasThread=thread}
                                Button("Tạo nhắc hẹn"){showingMore=false;store.reminderThread=thread}
                                if store.supports("start_call"){Button("Gọi video"){showingMore=false;store.startCall(video:true)}}
                                Button("Tin đã lưu và nhắc hẹn"){showingMore=false;store.showingInspector=false;store.workspaceSection = .saved}
                                if store.supports("sync_history"){Button("Đồng bộ lịch sử"){store.threadCommand("sync_history",thread:thread)}}
                            }.buttonStyle(.plain).padding(18).frame(width:240,alignment:.leading)
                        }

                }.foregroundStyle(.tint)
                VStack(alignment:.leading,spacing:12){InspectorLibrary(thread:thread,initialTab:thread.isGroup ? "members":"photos")}
                    .padding(18).background(Color(nsColor:.textBackgroundColor).opacity(0.92),in:RoundedRectangle(cornerRadius:20))
                Text("Nội dung thư viện lấy từ phần lịch sử đã tải trên máy.").font(.caption).foregroundStyle(.secondary)
            }.padding(22).frame(maxWidth:720).frame(maxWidth:.infinity)
        }.background(.regularMaterial)
         .onAppear{if thread.isGroup,store.supports("get_group_members"){store.threadCommand("get_group_members",thread:thread)}}
    }
    private func tile(_ icon:String,_ title:String,run:@escaping()->Void)->some View {
        Button(action:run){VStack(spacing:7){Image(systemName:icon).font(.title2);Text(title).font(.callout)}.frame(maxWidth:.infinity,minHeight:68).background(Color(nsColor:.textBackgroundColor).opacity(0.9),in:RoundedRectangle(cornerRadius:18))}.buttonStyle(LivelyButtonStyle())
    }
}
