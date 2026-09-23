import Foundation

public enum CarouselTimingMode: String, Sendable, CaseIterable, Identifiable {
    case uniform
    case byState

    public var id: String { rawValue }
}

public struct CarouselTimingConfiguration: Sendable, Equatable {
    public let mode: CarouselTimingMode
    public let uniformDuration: TimeInterval

    public init(mode: CarouselTimingMode = .uniform, uniformDuration: TimeInterval = 5) {
        self.mode = mode
        self.uniformDuration = [3.0, 5.0, 10.0].contains(uniformDuration) ? uniformDuration : 5
    }

    public func duration(for state: SessionRuntimeState) -> TimeInterval? {
        guard state != .idle else { return nil }
        if mode == .uniform { return uniformDuration }
        switch state {
        case .attention: return 6
        case .completed: return 4
        case .running: return 2
        case .idle: return nil
        }
    }
}

public struct PresentationCycle: Sendable, Equatable {
    public let sessionID: String
    public let runtimeState: SessionRuntimeState
    public let timingModeSnapshot: CarouselTimingMode
    public let durationSnapshot: TimeInterval
    public let visibleFrom: Date
    public let deadline: Date
    public let generation: UInt64
}
