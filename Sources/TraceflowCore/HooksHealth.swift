import Foundation

public enum HooksHealthState: String, Sendable {
    case notInstalled
    case pendingVerification
    case healthy
    case error
}

public struct HooksHealth: Sendable {
    public let state: HooksHealthState
    public let detail: String
    public init(state: HooksHealthState, detail: String) { self.state = state; self.detail = detail }
}
