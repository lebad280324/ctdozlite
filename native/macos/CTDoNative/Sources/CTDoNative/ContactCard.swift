import SwiftUI
import NativeBridge

/// A shared contact (Zalo "danh thiếp"), read from the message card the core sends.
struct ContactCardInfo: Equatable {
    let userID: String
    let name: String
    let avatar: String?
    let qr: URL?

    init?(_ message: MessageSnapshot) {
        guard message.card?["kind"]?.string == "contact", let id = message.card?["user_id"]?.string, !id.isEmpty else { return nil }
        userID = id
        name = message.card?["name"]?.string ?? message.linkTitle ?? ""
        avatar = message.card?["avatar"]?.string
        qr = safeWebURL(message.card?["qr"]?.string)
    }
}

/// Name card in the transcript: identity and QR code on a tinted panel, with "Kết bạn" and "Nhắn tin".
struct ContactShareCard: View {
    @EnvironmentObject private var store: AppStore
    let info: ContactCardInfo
    let time: Date
    @State private var showingProfile = false

    private var isSelf: Bool { info.userID == store.session.uin }
    private var friendship: String? { store.profiles[info.userID]?.friendship }
    private var canAdd: Bool {
        !isSelf && store.supports("add_friend") && (friendship == "Stranger" || friendship == nil && !store.threads.contains { $0.id == info.userID })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Button { showingProfile = true } label: {
                    HStack(spacing: 10) {
                        AvatarView(name: info.name, url: info.avatar, size: 46)
                            .overlay { Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: info.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                            Text(friendship == "Friend" ? "Bạn bè" : "Danh thiếp Zalo").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .buttonStyle(.plain).help("Xem thông tin")
                .windowBoundedPopover(isPresented: $showingProfile) {
                    ContactProfilePopover(userID: info.userID, name: info.name, avatar: info.avatar) { showingProfile = false }
                }
                Spacer(minLength: 8)
                if let qr = info.qr {
                    AsyncImage(url: qr) { phase in
                        if let image = phase.image { image.resizable().interpolation(.none).scaledToFit() }
                        else { Color.white.opacity(0.6) }
                    }
                    .frame(width: 64, height: 64).padding(4)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture { NotificationCenter.default.post(name: .openImageViewer, object: qr) }
                    .help("Mã QR của \(info.name)")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.13, green: 0.36, blue: 0.85), Color(red: 0.2, green: 0.5, blue: 0.95)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            HStack(spacing: 0) {
                if canAdd {
                    footerButton("Kết bạn") {
                        store.send("add_friend", parameters: ["user_id": .string(info.userID)])
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            store.requestProfile(info.userID, force: true)
                        }
                    }
                    .disabled(store.busy.contains("add_friend"))
                    Divider().frame(height: 22)
                }
                if !isSelf {
                    footerButton("Nhắn tin") { store.openDirect(userID: info.userID, name: info.name, avatar: info.avatar) }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text(time, format: .dateTime.hour().minute()).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    .padding(.trailing, 9).padding(.bottom, isSelf ? 6 : 2)
            }
            .frame(minHeight: isSelf ? 22 : 0)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)) }
        .onAppear { if !isSelf { store.requestProfile(info.userID) } }
        .accessibilityElement(children: .contain).accessibilityLabel("Danh thiếp \(info.name)")
    }

    private func footerButton(_ title: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
