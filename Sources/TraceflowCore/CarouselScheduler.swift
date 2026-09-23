import Foundation

public enum CarouselSwitchReason: Sendable, Equatable {
    case initial
    case redPreemption
    case yellowPreemption
    case redQueue
    case yellowQueue
    case greenQueue
    case rotation
    case stateChanged
    case selectionChanged
    case placeholder
}

public struct CarouselDecision: Sendable, Equatable {
    public let sessionID: String?
    public let reason: CarouselSwitchReason
    public let animated: Bool
    public let previousSessionID: String?
    public let cycle: PresentationCycle?

    public init(sessionID: String?, reason: CarouselSwitchReason, animated: Bool, cycle: PresentationCycle? = nil, previousSessionID: String? = nil) {
        self.sessionID = sessionID
        self.reason = reason
        self.animated = animated
        self.cycle = cycle
        self.previousSessionID = previousSessionID
    }
}

public struct CarouselScheduler: Sendable {
    public private(set) var currentSessionID: String?
    public private(set) var displayedSince: Date?
    public private(set) var currentCycle: PresentationCycle?
    private var timingConfiguration = CarouselTimingConfiguration()
    private var generation: UInt64 = 0
    private var redQueue: [String] = []
    private var yellowQueue: [String] = []
    private var greenQueue: [String] = []
    private var states: [String: SessionRuntimeState] = [:]
    private var rotationOrder: [String] = []
    private var included: Set<String> = []
    private var hasPresentedPlaceholder = false

    public init() {}

    public mutating func updateTimingConfiguration(_ configuration: CarouselTimingConfiguration) {
        timingConfiguration = configuration
    }

    @discardableResult
    public mutating func updateSessions(
        _ sessions: [SessionSnapshot],
        now: Date,
        updateExistingStates: Bool = true,
        processNewlyIncluded: Bool = true
    ) -> CarouselDecision? {
        let previousIncluded = included
        rotationOrder = sessions.sorted { $0.persisted.rotationIndex < $1.persisted.rotationIndex }.map(\.id)
        included = Set(sessions.lazy.filter { $0.persisted.isIncludedInHUD }.map(\.id))
        let sessionIDs = Set(sessions.map(\.id))
        states = states.filter { sessionIDs.contains($0.key) }
        for session in sessions where updateExistingStates || states[session.id] == nil {
            states[session.id] = session.state
        }
        var decision: CarouselDecision?
        if processNewlyIncluded && !previousIncluded.isEmpty {
            let newlyIncluded = rotationOrder.filter { included.contains($0) && !previousIncluded.contains($0) && states[$0] != .idle }
            let ordered = newlyIncluded.sorted {
                let left = priority(states[$0] ?? .idle), right = priority(states[$1] ?? .idle)
                if left != right { return left > right }
                return (rotationOrder.firstIndex(of: $0) ?? 0) < (rotationOrder.firstIndex(of: $1) ?? 0)
            }
            for id in ordered {
                if let result = queueOrPreempt(id, now: now, allowPreemption: decision == nil && (currentSessionID == nil || eligibleIDs.contains(currentSessionID!))) { decision = result }
            }
        }
        return decision ?? reconcile(now: now, reason: .selectionChanged)
    }

    public mutating func reportStateChange(
        sessionID: String,
        newState: SessionRuntimeState,
        stateChanged: Bool,
        now: Date
    ) -> CarouselDecision? {
        states[sessionID] = newState
        guard stateChanged else { return nil }
        removeFromQueues(sessionID)
        guard included.contains(sessionID) else { return nil }
        if currentSessionID == sessionID {
            if newState == .idle { return reconcile(now: now, reason: .selectionChanged) }
            pruneQueues()
            if let higher = highestQueuedPriority(), higher > priority(newState) {
                append(sessionID, state: newState)
                return selectQueuedOrRotated(now: now, fallbackReason: .stateChanged)
            }
            beginCycle(sessionID, state: newState, now: now, animated: false)
            return CarouselDecision(sessionID: sessionID, reason: .stateChanged, animated: false, cycle: currentCycle, previousSessionID: sessionID)
        }
        guard newState != .idle else { return nil }
        return queueOrPreempt(sessionID, now: now)
    }

    public mutating func advance(now: Date) -> CarouselDecision? {
        guard eligibleIDs.count > 1, let currentCycle,
              now >= currentCycle.deadline else { return nil }
        return selectQueuedOrRotated(now: now, fallbackReason: .rotation)
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
            let previous = currentSessionID
            currentSessionID = nil
            displayedSince = now
            currentCycle = nil
            hasPresentedPlaceholder = true
            return CarouselDecision(sessionID: nil, reason: .placeholder, animated: false, previousSessionID: previous)
        }
        if let currentSessionID, eligible.contains(currentSessionID) { return nil }

        let previous = currentSessionID
        let next = dequeueValidRed()
            ?? dequeueValidYellow()
            ?? dequeueValidGreen()
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
        let previous = currentSessionID
        removeFromQueues(sessionID)
        currentSessionID = sessionID
        displayedSince = now
        hasPresentedPlaceholder = false
        beginCycle(sessionID, state: states[sessionID] ?? .idle, now: now, animated: animated)
        return CarouselDecision(sessionID: sessionID, reason: reason, animated: animated, cycle: currentCycle, previousSessionID: previous)
    }

    private mutating func beginCycle(_ sessionID: String, state: SessionRuntimeState, now: Date, animated: Bool) {
        guard let duration = timingConfiguration.duration(for: state) else { currentCycle = nil; return }
        generation &+= 1
        let visibleFrom = now.addingTimeInterval(animated ? HUDTitleTransition.maximumDuration : 0)
        currentCycle = PresentationCycle(
            sessionID: sessionID,
            runtimeState: state,
            timingModeSnapshot: timingConfiguration.mode,
            durationSnapshot: duration,
            visibleFrom: visibleFrom,
            deadline: visibleFrom.addingTimeInterval(duration),
            generation: generation
        )
    }

    private mutating func nextInRotation() -> String? {
        let available = rotationOrder.filter(eligibleIDs.contains)
        guard !available.isEmpty else { return nil }
        guard let currentSessionID,
              let index = available.firstIndex(of: currentSessionID) else { return available[0] }
        return available.count > 1 ? available[(index + 1) % available.count] : nil
    }

    private mutating func pruneQueues() {
        let eligible = eligibleIDs
        redQueue.removeAll { id in
            id == currentSessionID || !eligible.contains(id) || states[id] != .attention
        }
        yellowQueue.removeAll { $0 == currentSessionID || !eligible.contains($0) || states[$0] != .completed }
        greenQueue.removeAll { $0 == currentSessionID || !eligible.contains($0) || states[$0] != .running }
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

    private mutating func dequeueValidYellow() -> String? {
        while !yellowQueue.isEmpty {
            let candidate = yellowQueue.removeFirst()
            if candidate != currentSessionID, eligibleIDs.contains(candidate), states[candidate] == .completed { return candidate }
        }
        return nil
    }

    private mutating func dequeueValidGreen() -> String? {
        while !greenQueue.isEmpty {
            let candidate = greenQueue.removeFirst()
            if candidate != currentSessionID, eligibleIDs.contains(candidate), states[candidate] == .running { return candidate }
        }
        return nil
    }

    private mutating func selectQueuedOrRotated(now: Date, fallbackReason: CarouselSwitchReason) -> CarouselDecision? {
        pruneQueues()
        if let next = dequeueValidRed() { return select(next, now: now, reason: fallbackReason == .rotation ? .redQueue : fallbackReason, animated: next != currentSessionID) }
        if let next = dequeueValidYellow() { return select(next, now: now, reason: fallbackReason == .rotation ? .yellowQueue : fallbackReason, animated: next != currentSessionID) }
        if let next = dequeueValidGreen() { return select(next, now: now, reason: fallbackReason == .rotation ? .greenQueue : fallbackReason, animated: next != currentSessionID) }
        guard let next = nextInRotation() else { return nil }
        return select(next, now: now, reason: fallbackReason, animated: next != currentSessionID)
    }

    private mutating func queueOrPreempt(_ id: String, now: Date, allowPreemption: Bool = true) -> CarouselDecision? {
        guard let state = states[id], state != .idle, included.contains(id), id != currentSessionID else { return nil }
        if currentSessionID == nil {
            return allowPreemption ? select(id, now: now, reason: .initial, animated: false) : nil
        }
        if allowPreemption, let current = currentSessionID, priority(state) > priority(states[current] ?? .idle) {
            if let previousState = states[current], previousState != .idle, eligibleIDs.contains(current) {
                append(current, state: previousState)
            }
            return select(id, now: now, reason: state == .attention ? .redPreemption : .yellowPreemption, animated: true)
        }
        append(id, state: state)
        return nil
    }

    private mutating func append(_ id: String, state: SessionRuntimeState) {
        removeFromQueues(id)
        switch state {
        case .attention: redQueue.append(id)
        case .completed: yellowQueue.append(id)
        case .running: greenQueue.append(id)
        case .idle: break
        }
    }

    private mutating func removeFromQueues(_ id: String) {
        remove(id, from: &redQueue)
        remove(id, from: &yellowQueue)
        remove(id, from: &greenQueue)
    }

    private func highestQueuedPriority() -> Int? {
        if !redQueue.isEmpty { return 3 }
        if !yellowQueue.isEmpty { return 2 }
        if !greenQueue.isEmpty { return 1 }
        return nil
    }

    private func priority(_ state: SessionRuntimeState) -> Int {
        switch state {
        case .idle: 0
        case .running: 1
        case .completed: 2
        case .attention: 3
        }
    }

    private func remove(_ sessionID: String, from queue: inout [String]) {
        queue.removeAll { $0 == sessionID }
    }
}
