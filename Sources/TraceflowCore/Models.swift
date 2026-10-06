import Foundation

public enum SessionRuntimeState: String, Codable, Sendable, CaseIterable {
    case idle
    case running
    case attention
    case completed
}

public enum HookEventName: String, Codable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case permissionRequest = "PermissionRequest"
    case postToolUse = "PostToolUse"
    case stop = "Stop"
    case interrupt = "Interrupt"
    case sessionEnd = "SessionEnd"
}

public struct HookPayload: Codable, Sendable, Equatable {
    public let sessionID: String
    public let cwd: String?
    public let eventName: HookEventName
    public let turnID: String?
    public let toolName: String?
    public let toolUseID: String?
    public let source: String?
    public let prompt: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case cwd
        case eventName = "hook_event_name"
        case turnID = "turn_id"
        case toolName = "tool_name"
        case toolUseID = "tool_use_id"
        case source
        case prompt
    }

    public init(
        sessionID: String,
        cwd: String? = nil,
        eventName: HookEventName,
        turnID: String? = nil,
        toolName: String? = nil,
        toolUseID: String? = nil,
        source: String? = nil,
        prompt: String? = nil
    ) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.eventName = eventName
        self.turnID = turnID
        self.toolName = toolName
        self.toolUseID = toolUseID
        self.source = source
        self.prompt = prompt
    }
}

public struct HookEnvelope: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let eventID: String
    public let capturedUptimeNanoseconds: UInt64
    public let forwardedAt: Date
    public let payload: HookPayload

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case eventID = "event_id"
        case capturedUptimeNanoseconds = "captured_uptime_ns"
        case forwardedAt = "forwarded_at"
        case payload
    }

    public init(
        schemaVersion: Int = 1,
        eventID: String,
        capturedUptimeNanoseconds: UInt64,
        forwardedAt: Date,
        payload: HookPayload
    ) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.capturedUptimeNanoseconds = capturedUptimeNanoseconds
        self.forwardedAt = forwardedAt
        self.payload = payload
    }
}

public struct PersistedSession: Codable, Sendable, Equatable, Identifiable {
    public var id: String { sessionID }
    public let sessionID: String
    public var agentType: String
    public var projectPath: String?
    public var projectName: String?
    public var codexThreadName: String?
    public var markerColorHex: String?
    public var customTitle: String?
    public var isIncludedInHUD: Bool
    public let discoveredAt: Date
    public var lastUpdatedAt: Date
    public var lastActivityAt: Date?
    public var settingsListSortAt: Date?
    public let rotationIndex: Int

    public init(
        sessionID: String,
        agentType: String = "codex",
        projectPath: String? = nil,
        projectName: String? = nil,
        codexThreadName: String? = nil,
        customTitle: String? = nil,
        markerColorHex: String? = nil,
        isIncludedInHUD: Bool = false,
        discoveredAt: Date,
        lastUpdatedAt: Date,
        lastActivityAt: Date? = nil,
        settingsListSortAt: Date? = nil,
        rotationIndex: Int
    ) {
        self.sessionID = sessionID
        self.agentType = agentType
        self.projectPath = projectPath
        self.projectName = projectName
        self.codexThreadName = codexThreadName
        self.customTitle = customTitle
        self.markerColorHex = SessionMarkerColor.normalized(markerColorHex)
        self.isIncludedInHUD = isIncludedInHUD
        self.discoveredAt = discoveredAt
        self.lastUpdatedAt = lastUpdatedAt
        self.lastActivityAt = lastActivityAt
        self.settingsListSortAt = settingsListSortAt
        self.rotationIndex = rotationIndex
    }

    enum CodingKeys: String, CodingKey {
        case sessionID, agentType, projectPath, projectName, codexThreadName, customTitle, isIncludedInHUD, discoveredAt, lastUpdatedAt, lastActivityAt, settingsListSortAt, rotationIndex, markerColorHex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        agentType = try container.decode(String.self, forKey: .agentType)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
        codexThreadName = try container.decodeIfPresent(String.self, forKey: .codexThreadName)
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        isIncludedInHUD = try container.decode(Bool.self, forKey: .isIncludedInHUD)
        discoveredAt = try container.decode(Date.self, forKey: .discoveredAt)
        lastUpdatedAt = try container.decode(Date.self, forKey: .lastUpdatedAt)
        lastActivityAt = try container.decodeIfPresent(Date.self, forKey: .lastActivityAt)
        settingsListSortAt = try container.decodeIfPresent(Date.self, forKey: .settingsListSortAt)
        rotationIndex = try container.decode(Int.self, forKey: .rotationIndex)
        markerColorHex = SessionMarkerColor.normalized(try? container.decode(String.self, forKey: .markerColorHex))
    }

    public var effectiveSettingsListSortAt: Date {
        settingsListSortAt ?? lastUpdatedAt
    }
}

public struct SessionSnapshot: Sendable, Equatable, Identifiable {
    public var id: String { persisted.sessionID }
    public var persisted: PersistedSession
    public var state: SessionRuntimeState
    public var conversationSummary: String?
    public var lastAppliedUptimeNanoseconds: UInt64?
    public var completedAt: Date?

    public init(
        persisted: PersistedSession,
        state: SessionRuntimeState = .idle,
        conversationSummary: String? = nil,
        lastAppliedUptimeNanoseconds: UInt64? = nil,
        completedAt: Date? = nil
    ) {
        self.persisted = persisted
        self.state = state
        self.conversationSummary = conversationSummary
        self.lastAppliedUptimeNanoseconds = lastAppliedUptimeNanoseconds
        self.completedAt = completedAt
    }

    public var effectiveConversationTitle: String? {
        if let customTitle = persisted.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customTitle.isEmpty { return customTitle }
        return defaultConversationTitle
    }

    public var defaultConversationTitle: String? {
        for candidate in [conversationSummary, persisted.codexThreadName] {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    public var sessionListTitle: String {
        effectiveConversationTitle ?? "未命名会话"
    }

    public var displayTitle: String {
        TitleBuilder.displayTitle(
            projectName: persisted.projectName,
            conversationSummary: effectiveConversationTitle
        )
    }
}

public enum EventApplyRejection: Sendable, Equatable {
    case unsupportedSchema
    case duplicate
    case outOfOrder
    case ignoredCompaction
}

public struct EventApplyResult: Sendable, Equatable {
    public let accepted: Bool
    public let rejection: EventApplyRejection?
    public let oldState: SessionRuntimeState
    public let newState: SessionRuntimeState
    public let stateChanged: Bool
    public let titleChanged: Bool

    public init(
        accepted: Bool,
        rejection: EventApplyRejection? = nil,
        oldState: SessionRuntimeState,
        newState: SessionRuntimeState,
        stateChanged: Bool,
        titleChanged: Bool
    ) {
        self.accepted = accepted
        self.rejection = rejection
        self.oldState = oldState
        self.newState = newState
        self.stateChanged = stateChanged
        self.titleChanged = titleChanged
    }
}
