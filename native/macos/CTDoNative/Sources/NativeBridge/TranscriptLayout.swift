import Foundation

public struct TranscriptRow: Identifiable, Sendable {
    public let message: MessageSnapshot
    public let showsTimestamp: Bool
    public let startsRun: Bool
    public let endsRun: Bool
    public var id: String { message.id }
}

/// A single pass over a single filtered snapshot, independent of visible row count.
public enum TranscriptLayout {
    public static func rows(_ messages: [MessageSnapshot], mediaOnly: Bool = false) -> [TranscriptRow] {
        let visible = mediaOnly ? messages.filter { $0.imageURL != nil || $0.fileURL != nil } : messages
        guard !visible.isEmpty else { return [] }
        let calendar = Calendar.current
        func stamp(_ index: Int) -> Bool {
            if index == 0 { return true }
            let previous = visible[index - 1].date, current = visible[index].date
            return !calendar.isDate(previous, inSameDayAs: current) || current.timeIntervalSince(previous) >= 900
        }
        func same(_ lhs: MessageSnapshot, _ rhs: MessageSnapshot) -> Bool {
            lhs.isOutgoing == rhs.isOutgoing && (lhs.isOutgoing || (lhs.senderID == rhs.senderID && lhs.senderName == rhs.senderName))
        }
        let stamps = visible.indices.map(stamp)
        return visible.indices.map { index in
            TranscriptRow(message: visible[index], showsTimestamp: stamps[index],
                startsRun: index == 0 || stamps[index] || !same(visible[index-1],visible[index]),
                endsRun: index == visible.count-1 || stamps[index+1] || !same(visible[index],visible[index+1]))
        }
    }
}
