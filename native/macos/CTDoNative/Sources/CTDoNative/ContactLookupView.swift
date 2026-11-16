import SwiftUI
import NativeBridge

struct ContactLookupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Tìm bạn trên Zalo").font(.title2.weight(.semibold))
                Spacer()
                Button("Đóng") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Nhập số điện thoại để xem thông tin và gửi lời mời kết bạn.").foregroundStyle(.secondary)
            HStack {
                TextField("Số điện thoại", text: $phone).textFieldStyle(.roundedBorder).onSubmit { lookup() }
                Button("Tìm kiếm") { lookup() }.buttonStyle(.borderedProminent)
                    .disabled(phone.trimmingCharacters(in: .whitespaces).isEmpty || store.busy.contains("lookup_phone"))
            }
            if store.busy.contains("lookup_phone") { ProgressView("Đang tìm kiếm…") }
            if let result = store.contactResult, let uid = result["user_id"]?.string {
                HStack(spacing: 14) {
                    AvatarView(name: result["display_name"]?.string ?? "", url: result["avatar"]?.string, size: 60)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: result["display_name"]?.string ?? "Người dùng Zalo").font(.headline)
                        if let thread = store.threads.first(where: { $0.id == uid }) {
                            Button("Mở cuộc trò chuyện") { store.selectThread(thread.id); dismiss() }
                        }
                        if store.supports("add_friend") {
                            Button("Gửi lời mời kết bạn") { store.send("add_friend", parameters: ["user_id": .string(uid)]) }
                                .disabled(store.busy.contains("add_friend"))
                        }
                        if store.supports("undo_friend") {
                            Button("Thu hồi lời mời đã gửi") { store.send("undo_friend", parameters: ["user_id": .string(uid)]) }
                                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                                .disabled(store.busy.contains("undo_friend"))
                        }
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).nativeGlass()
            }
            if let error = store.error { Text(verbatim: error).font(.callout).foregroundStyle(.orange) }
            Text(verbatim: store.connection).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.padding(26).frame(width: 470, height: 350)
    }
    private func lookup() {
        store.contactResult = nil; store.error = nil
        store.send("lookup_phone", parameters: ["phone": .string(phone)])
    }
}
