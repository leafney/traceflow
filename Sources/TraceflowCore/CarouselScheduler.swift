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
    private var hasPresentedPlaceholder = false

    public init() {}

    @discardableResult
    public mutating func updateSessions(
        _ sessions: [SessionSnapshot],
        now: Date,
        updateExistingStates: Bool = true
    ) -> CarouselDecision? {
        rotationOrder = sessions.sorted { $0.persisted.rotationIndex < $1.persisted.rotationIndex }.map(\.id)
        included = Set(sessions.lazy.filter { $0.persisted.isIncludedInHUD }.map(\.id))
        let sessionIDs = Set(sessions.map(\.id))
        states = states.filter { sessionIDs.contains($0.key) }
        for session in sessions where updateExistingStates || states[session.id] == nil {
            states[session.id] = session.state
        }
        return reconcile(now: now, reason: .selectionChanged)
    }

    public mutating func reportStateChange(
        sessionID: String,
        newState: SessionRuntimeState,
        stateChanged: Bool,
        now: Date
    ) -> CarouselDecision? {
        states[sessionID] = newState
        pruneQueues()
        guard included.contains(sessionID), stateChanged else { return nil }

        if newState == .idle {
            remove(sessionID, from: &redQueue)
            remove(sessionID, from: &eventQueue)
            guard currentSessionID == sessionID else { return nil }
            return reconcile(now: now, reason: .selectionChanged)
        }

        if currentSessionID == sessionID {
            remove(sessionID, from: &redQueue)
            remove(sessionID, from: &eventQueue)
            if newState == .attention { displayedSince = now }
            return nil
        }

        switch newState {
        case .attention:
            remove(sessionID, from: &eventQueue)
            guard let currentSessionID else {
                return select(sessionID, now: now, reason: .initial, animated: false)
            }
            if states[currentSessionID] != .attention {
                return select(sessionID, now: now, reason: .redPreemption, animated: true)
            }
            appendUnique(sessionID, to: &redQueue)
            return nil

        case .running, .completed:
            remove(sessionID, from: &redQueue)
            guard currentSessionID != nil else {
                return select(sessionID, now: now, reason: .initial, animated: false)
            }
            appendUnique(sessionID, to: &eventQueue)
            return nil

        case .idle:
            return nil
        }
    }

    public mutating func advance(now: Date, displayDuration: TimeInterval) -> CarouselDecision? {
        guard eligibleIDs.count > 1, let displayedSince,
              now.timeIntervalSince(displayedSince) >= displayDuration else { return nil }
        pruneQueues()
        if let next = dequeueValidRed() {
            return select(next, now: now, reason: .redQueue, animated: true)
        }
        if let next = dequeueValidEvent() {
            return select(next, now: now, reason: .eventQueue, animated: true)
        }
        guard let next = nextInRotation() else { return nil }
        return select(next, now: now, reason: .rotation, animated: next != currentSessionID)
    }

    private var eligibleIDs: Set<String> {
        Set(states.compactMap { id, state in
            included.contains(id) && state != .idle ? id : nil
        })
    }

    private mutating func reconcile(now: Date, reason: CarouselSwitchReason) -> CarouselDecision? {
        pruneQueues()
        let eligible = eligibleIDs
        guard !eligible.isEmpty else {
            guard currentSessionID != nil || !hasPresentedPlaceholder else { return nil }
            currentSessionID = nil
            displayedSince = now
            hasPresentedPlaceholder = true
            return CarouselDecision(sessionID: nil, reason: .placeholder, animated: false)
        }
        if let currentSessionID, eligible.contains(currentSessionID) { return nil }

        let previous = currentSessionID
        let next = dequeueValidRed()
            ?? dequeueValidEvent()
            ?? rotationOrder.first(where: eligible.contains)
        guard let next else { return nil }
        return select(
            next,
            now: now,
            reason: previous == nil ? .initial : reason,
            animated: previous != nil && previous != next
        )
    }

    private mutating func select(
        _ sessionID: String,
        now: Date,
        reason: CarouselSwitchReason,
        animated: Bool
    ) -> CarouselDecision {
        remove(sessionID, from: &redQueue)
        remove(sessionID, from: &eventQueue)
        currentSessionID = sessionID
        displayedSince = now
        hasPresentedPlaceholder = false
        return CarouselDecision(sessionID: sessionID, reason: reason, animated: animated)
    }

    private mutating func nextInRotation() -> String? {
        let available = rotationOrder.filter(eligibleIDs.contains)
        guard !available.isEmpty else { return nil }
        guard let currentSessionID,
              let index = available.firstIndex(of: currentSessionID) else { return available[0] }
        return available[(index + 1) % available.count]
    }

    private mutating func pruneQueues() {
        let eligible = eligibleIDs
        redQueue.removeAll { id in
            id == currentSessionID || !eligible.contains(id) || states[id] != .attention
        }
        eventQueue.removeAll { id in
            guard id != currentSessionID,
                  eligible.contains(id),
                  let state = states[id] else { return true }
            return state != .running && state != .completed
        }
        for id in redQueue { remove(id, from: &eventQueue) }
    }

    private mutating func dequeueValidRed() -> String? {
        while !redQueue.isEmpty {
            let candidate = redQueue.removeFirst()
            if candidate != currentSessionID,
               eligibleIDs.contains(candidate),
               states[candidate] == .attention {
                return candidate
            }
        }
        return nil
    }

    private mutating func dequeueValidEvent() -> String? {
        while !eventQueue.isEmpty {
            let candidate = eventQueue.removeFirst()
            if candidate != currentSessionID,
               eligibleIDs.contains(candidate),
               let state = states[candidate], state == .running || state == .completed {
                return candidate
            }
        }
        return nil
    }

    private func appendUnique(_ sessionID: String, to queue: inout [String]) {
        if !queue.contains(sessionID) { queue.append(sessionID) }
    }

    private func remove(_ sessionID: String, from queue: inout [String]) {
        queue.removeAll { $0 == sessionID }
    }
}
