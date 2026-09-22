import Foundation

public enum HooksHealthState: String, Sendable {
    case notInstalled
    case needsRepair
    case pendingVerification
    case healthy
    case error
}

public enum LocalCommunicationState: String, Sendable {
    case healthy
    case testing
    case error
}

public struct LocalCommunicationHealth: Sendable {
    public let state: LocalCommunicationState
    public let detail: String
    public init(state: LocalCommunicationState, detail: String) { self.state = state; self.detail = detail }
}

public struct HooksHealth: Sendable {
    public let state: HooksHealthState
    public let detail: String
    public init(state: HooksHealthState, detail: String) { self.state = state; self.detail = detail }
}
