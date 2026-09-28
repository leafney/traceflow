import Foundation

public enum SessionDiscoveryRequest: Sendable, Equatable {
    case automatic
    case manual
}

public struct SessionDiscoveryCoordinator: Sendable {
    public private(set) var activeRequest: SessionDiscoveryRequest?
    public private(set) var nextAutomaticAt: Date = .distantPast
    private var pendingManual = false
    private var suppressedUntil: [String: Date] = [:]

    public init() {}

    public mutating func openSettings(now: Date) -> SessionDiscoveryRequest? {
        guard activeRequest == nil else { return nil }
        activeRequest = .automatic
        return .automatic
    }

    public mutating func poll(now: Date, isSettingsVisible: Bool) -> SessionDiscoveryRequest? {
        guard isSettingsVisible, activeRequest == nil, now >= nextAutomaticAt else { return nil }
        activeRequest = .automatic
        return .automatic
    }

    public mutating func requestManual() -> SessionDiscoveryRequest? {
        if activeRequest == .automatic {
            pendingManual = true
            return nil
        }
        guard activeRequest == nil else { return nil }
        activeRequest = .manual
        return .manual
    }

    public mutating func finish(now: Date) -> SessionDiscoveryRequest? {
        activeRequest = nil
        nextAutomaticAt = now.addingTimeInterval(15)
        if pendingManual {
            pendingManual = false
            activeRequest = .manual
            return .manual
        }
        return nil
    }

    public mutating func suppress(_ ids: [String], now: Date) {
        let deadline = now.addingTimeInterval(RecentSessionSelector.window)
        for id in ids { suppressedUntil[id] = deadline }
    }

    public mutating func permitsAutomaticImport(_ id: String, now: Date) -> Bool {
        guard let deadline = suppressedUntil[id] else { return true }
        if now < deadline { return false }
        suppressedUntil.removeValue(forKey: id)
        return true
    }

    public mutating func clearSuppression() {
        suppressedUntil.removeAll()
    }
}
