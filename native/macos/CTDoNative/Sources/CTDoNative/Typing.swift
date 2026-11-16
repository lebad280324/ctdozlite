import SwiftUI
import NativeBridge

/// Who is typing where, from Zalo's `typing` controls. Kept apart from `AppStore` so a typing
/// event redraws only the rows and the bar that show it.
@MainActor
final class TypingTracker: ObservableObject {
    /// Thread ID → person ID → when the mark lapses. Zalo repeats the control every few seconds while
    /// typing continues and sends nothing when it stops, so each mark lapses on its own.
    @Published private(set) var active: [String: [String: Date]] = [:]
    private static let lifetime: TimeInterval = 6

    func note(thread: String, user: String) {
        let until = Date().addingTimeInterval(Self.lifetime)
        active[thread, default: [:]][user] = until
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((Self.lifetime + 0.2) * 1_000_000_000))
            self?.expire(thread: thread)
        }
    }

    /// A message from the person ends their typing mark at once.
    func stop(thread: String, user: String) {
        guard active[thread]?[user] != nil else { return }
        active[thread]?[user] = nil
        if active[thread]?.isEmpty == true { active[thread] = nil }
    }

    func reset() { if !active.isEmpty { active = [:] } }

    func users(in thread: String) -> [String] {
        let now = Date()
        return (active[thread] ?? [:]).filter { $0.value > now }.keys.sorted()
    }

    private func expire(thread: String) {
        let now = Date()
        guard let marks = active[thread] else { return }
        let live = marks.filter { $0.value > now }
        if live.count != marks.count { active[thread] = live.isEmpty ? nil : live }
    }
}

/// Three dots that rise in turn, as in the typing bubble of Messages.
struct TypingDots: View {
    var color: Color = .secondary
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reducedMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = reducedMotion ? 0 : max(0, sin((t * 2 * .pi / 1.2) - Double(index) * 0.7))
                    Circle().fill(color).frame(width: 4.5, height: 4.5)
                        .opacity(0.45 + 0.55 * phase).offset(y: -2.5 * phase)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// "<name> đang soạn tin" above the composer.
struct TypingBar: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var tracker: TypingTracker
    let thread: ThreadSnapshot

    var body: some View {
        let users = tracker.users(in: thread.id)
        Group {
            if !users.isEmpty {
                HStack(spacing: 7) {
                    Text(verbatim: label(users)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    TypingDots()
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .nativeGlass(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine).accessibilityLabel(label(users))
            }
        }
        .animation(.easeOut(duration: 0.18), value: users)
    }

    private func label(_ users: [String]) -> String {
        guard thread.isGroup else { return "\(thread.name) đang soạn tin" }
        let names = users.prefix(2).map { store.typingName($0, in: thread.id) }
        if users.count > 2 { return "\(names.joined(separator: ", ")) và \(users.count - 2) người khác đang soạn tin" }
        return "\(names.joined(separator: " và ")) đang soạn tin"
    }
}

extension AppStore {
    /// Name for a typing person: nickname, group member name, profile, last message sender.
    func typingName(_ userID: String, in threadID: String) -> String {
        if let alias = aliases[userID], !alias.isEmpty { return alias }
        if let member = features.members[threadID]?.first(where: { $0.id == userID }) {
            let name = member.string("name", "display_name"); if !name.isEmpty { return name }
        }
        if let name = profiles[userID]?.name, !name.isEmpty { return name }
        if let message = messages[threadID]?.last(where: { $0.senderID == userID }), !message.senderName.isEmpty { return message.senderName }
        return "Một thành viên"
    }
}
