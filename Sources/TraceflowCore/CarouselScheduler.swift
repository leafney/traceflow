import Foundation

public enum CarouselSwitchReason: Sendable, Equatable {
    case initial
    case redPreemption
    case redQueue
    case eventQueue
    case rotation
    case selectionChanged
    case placeholder
}

public struct CarouselDecision: Sendable, Equatable {
    public let sessionID: String?
    public let reason: CarouselSwitchReason
    public let animated: Bool

    public init(sessionID: String?, reason: CarouselSwitchReason, animated: Bool) {
        self.sessionID = sessionID
        self.reason = reason
        self.animated = animated
    }
}

public struct CarouselScheduler: Sendable {
    public private(set) var currentSessionID: String?
    public private(set) var displayedSince: Date?
    private var redQueue: [String] = []
    private var eventQueue: [String] = []
    private var states: [String: SessionRuntimeState] = [:]
    private var rotationOrder: [String] = []
    private var included: Set<String> = []

    public init() {}

    @discardableResult
    public mutating func updateSessions(_ sessions: [SessionSnapshot], now: Date) -> CarouselDecision? {
        rotationOrder = sessions.sorted { $0.persisted.rotationIndex < $1.persisted.rotationIndex }.map(\.id)
        included = Set(sessions.filter { $0.persisted.isIncludedInHUD }.map(\.id))
        states = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.state) })
        pruneQueues()

        guard !included.isEmpty else {
            currentSessionID = nil
            displayedSince = now
            return CarouselDecision(sessionID: nil, reason: .placeholder, animated: false)
        }
        if let currentSessionID, included.contains(currentSessionID) { return nil }
        let next = rotationOrder.first(where: included.contains)
        currentSessionID = next
        displayedSince = now
        return CarouselDecision(sessionID: next, reason: .selectionChanged, animated: included.count > 1)
    }

    public mutating func reportStateChange(
        sessionID: String,
        newState: SessionRuntimeState,
        stateChanged: Bool,
        now: Date
    ) -> CarouselDecision? {
        states[sessionID] = newState
        guard included.contains(sessionID), stateChanged else { return nil }
        guard included.count > 1 else {
            currentSessionID = sessionID
            displayedSince = now
            return CarouselDecision(sessionID: sessionID, reason: .initial, animated: false)
        }
        if currentSessionID == sessionID {
            remove(sessionID, from: &redQueue)
            remove(sessionID, from: &eventQueue)
            if newState == .attention { displayedSince = now }
            return nil
        }
        if newState == .attention {
            remove(sessionID, from: &eventQueue)
            if currentSessionID.flatMap({ states[$0] }) != .attention {
                remove(sessionID, from: &redQueue)
                currentSessionID = sessionID
                displayedSince = now
                return CarouselDecision(sessionID: sessionID, reason: .redPreemption, animated: true)
            }
            appendUnique(sessionID, to: &redQueue)
            return nil
        }
        remove(sessionID, from: &redQueue)
        appendUnique(sessionID, to: &eventQueue)
        return nil
    }

    public mutating func advance(now: Date, displayDuration: TimeInterval) -> CarouselDecision? {
        guard included.count > 1, let displayedSince,
              now.timeIntervalSince(displayedSince) >= displayDuration else { return nil }
        pruneQueues()
        let next: String?
        let reason: CarouselSwitchReason
        if !redQueue.isEmpty {
            next = redQueue.removeFirst()
            reason = .redQueue
        } else if !eventQueue.isEmpty {
            next = eventQueue.removeFirst()
            reason = .eventQueue
        } else {
            next = nextInRotation()
            reason = .rotation
        }
        guard let next else { return nil }
        currentSessionID = next
        self.displayedSince = now
        return CarouselDecision(sessionID: next, reason: reason, animated: true)
    }

    private func nextInRotation() -> String? {
        let available = rotationOrder.filter(included.contains)
        guard !available.isEmpty else { return nil }
        guard let currentSessionID,
              let index = available.firstIndex(of: currentSessionID) else { return available[0] }
        return available[(index + 1) % available.count]
    }

    private mutating func pruneQueues() {
        redQueue.removeAll { !included.contains($0) }
        eventQueue.removeAll { !included.contains($0) }
    }

    private func appendUnique(_ sessionID: String, to queue: inout [String]) {
        if !queue.contains(sessionID) { queue.append(sessionID) }
    }

    private func remove(_ sessionID: String, from queue: inout [String]) {
        queue.removeAll { $0 == sessionID }
    }
}
