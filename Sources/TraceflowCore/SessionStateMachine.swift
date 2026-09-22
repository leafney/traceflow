import Foundation

public struct SessionStateMachine: Sendable {
    public private(set) var snapshot: SessionSnapshot
    private var recentEventIDs: [String] = []
    private let eventCacheLimit: Int

    public init(snapshot: SessionSnapshot, eventCacheLimit: Int = 128) {
        self.snapshot = snapshot
        self.eventCacheLimit = max(1, eventCacheLimit)
    }

    public mutating func apply(_ envelope: HookEnvelope, now: Date) -> EventApplyResult {
        let oldState = snapshot.state
        let oldTitle = snapshot.displayTitle

        guard envelope.schemaVersion == 1 else {
            return rejected(.unsupportedSchema, oldState: oldState)
        }
        guard !recentEventIDs.contains(envelope.eventID) else {
            return rejected(.duplicate, oldState: oldState)
        }
        if let last = snapshot.lastAppliedUptimeNanoseconds,
           envelope.capturedUptimeNanoseconds < last {
            return rejected(.outOfOrder, oldState: oldState)
        }
        if envelope.payload.eventName == .sessionStart,
           envelope.payload.source == "compact" {
            return rejected(.ignoredCompaction, oldState: oldState)
        }

        remember(envelope.eventID)
        snapshot.lastAppliedUptimeNanoseconds = envelope.capturedUptimeNanoseconds
        snapshot.persisted.lastUpdatedAt = now
        if let cwd = envelope.payload.cwd {
            snapshot.persisted.projectPath = cwd
            snapshot.persisted.projectName = TitleBuilder.projectName(from: cwd)
        }
        if envelope.payload.eventName == .userPromptSubmit,
           snapshot.conversationSummary == nil {
            snapshot.conversationSummary = TitleBuilder.summary(from: envelope.payload.prompt)
        }

        switch envelope.payload.eventName {
        case .sessionStart, .interrupt, .sessionEnd:
            snapshot.state = .idle
            snapshot.completedAt = nil
        case .userPromptSubmit, .postToolUse:
            snapshot.state = .running
            snapshot.completedAt = nil
        case .permissionRequest:
            snapshot.state = .attention
            snapshot.completedAt = nil
        case .stop:
            snapshot.state = .completed
            snapshot.completedAt = now
        }

        return EventApplyResult(
            accepted: true,
            oldState: oldState,
            newState: snapshot.state,
            stateChanged: oldState != snapshot.state,
            titleChanged: oldTitle != snapshot.displayTitle
        )
    }

    @discardableResult
    public mutating func expireCompletion(now: Date, timeout: TimeInterval = 600) -> Bool {
        guard snapshot.state == .completed,
              let completedAt = snapshot.completedAt,
              now.timeIntervalSince(completedAt) >= timeout else { return false }
        snapshot.state = .idle
        snapshot.completedAt = nil
        snapshot.persisted.lastUpdatedAt = now
        return true
    }

    public mutating func setIncludedInHUD(_ included: Bool) {
        snapshot.persisted.isIncludedInHUD = included
    }

    public mutating func updatePersistedMetadata(_ persisted: PersistedSession) {
        precondition(persisted.sessionID == snapshot.persisted.sessionID)
        snapshot.persisted = persisted
    }

    private func rejected(_ rejection: EventApplyRejection, oldState: SessionRuntimeState) -> EventApplyResult {
        EventApplyResult(
            accepted: false,
            rejection: rejection,
            oldState: oldState,
            newState: oldState,
            stateChanged: false,
            titleChanged: false
        )
    }

    private mutating func remember(_ eventID: String) {
        recentEventIDs.append(eventID)
        if recentEventIDs.count > eventCacheLimit {
            recentEventIDs.removeFirst(recentEventIDs.count - eventCacheLimit)
        }
    }
}
