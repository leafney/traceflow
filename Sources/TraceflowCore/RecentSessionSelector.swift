import Foundation

public enum RecentSessionSelector {
    public static let window: TimeInterval = 600

    public static func select(from sessions: [SessionSnapshot], now: Date) -> [SessionSnapshot] {
        sessions.filter { session in
            guard let activity = session.persisted.lastActivityAt else { return false }
            let age = now.timeIntervalSince(activity)
            return age >= 0 && age < window
        }.sorted { lhs, rhs in
            let left = lhs.persisted.lastActivityAt!
            let right = rhs.persisted.lastActivityAt!
            if left != right { return left > right }
            return lhs.id < rhs.id
        }
    }
}
