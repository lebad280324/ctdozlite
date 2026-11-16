import Foundation
import Combine

/// Search terms stay on this Mac, scoped to the signed-in account and bounded to twelve entries.
@MainActor final class RecentSearchHistory: ObservableObject {
    @Published private(set) var queries: [String] = []
    private let defaults: UserDefaults
    private var key: String?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func activate(account: String, persistent: Bool) {
        key = persistent && !account.isEmpty ? "nativeRecentSearches.\(account)" : nil
        queries = key.flatMap { defaults.stringArray(forKey: $0) } ?? []
    }

    func remember(_ query: String) {
        let value = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !value.isEmpty else { return }
        queries.removeAll { $0.compare(value, options: [.caseInsensitive]) == .orderedSame }
        queries.insert(value, at: 0)
        queries = Array(queries.prefix(12))
        save()
    }

    func remove(_ query: String) { queries.removeAll { $0 == query }; save() }
    func clear() { queries = []; save() }
    private func save() { if let key { defaults.set(queries, forKey: key) } }
}
