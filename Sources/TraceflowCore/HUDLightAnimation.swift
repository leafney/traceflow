import Foundation

public struct HUDLightVisualParameters: Sendable, Equatable {
    public let scale: Double
    public let bodyOpacity: Double
    public let glowIntensity: Double
    public let isTimelinePaused: Bool

    public init(scale: Double, bodyOpacity: Double, glowIntensity: Double, isTimelinePaused: Bool) {
        self.scale = scale
        self.bodyOpacity = bodyOpacity
        self.glowIntensity = glowIntensity
        self.isTimelinePaused = isTimelinePaused
    }
}

public enum HUDLightAnimation {
    public static func parameters(
        for state: SessionRuntimeState,
        isActive: Bool,
        referenceTime: TimeInterval,
        reduceMotion: Bool
    ) -> HUDLightVisualParameters {
        guard isActive else {
            return HUDLightVisualParameters(scale: 1, bodyOpacity: 0.18, glowIntensity: 0, isTimelinePaused: true)
        }
        guard !reduceMotion else {
            return HUDLightVisualParameters(scale: 1, bodyOpacity: 1, glowIntensity: 1, isTimelinePaused: true)
        }

        let phase = phase(for: state, referenceTime: referenceTime)
        let bodyOpacity = state == .completed ? 1 : 0.18 + 0.82 * phase
        let glowIntensity = state == .completed ? 1 : phase
        return HUDLightVisualParameters(
            scale: 0.8 + 0.4 * phase,
            bodyOpacity: bodyOpacity,
            glowIntensity: glowIntensity,
            isTimelinePaused: false
        )
    }

    public static func phase(for state: SessionRuntimeState, referenceTime: TimeInterval) -> Double {
        let period: TimeInterval
        switch state {
        case .attention: period = 0.56
        case .running: period = 2.30
        case .completed: period = 2.80
        case .idle: return 0
        }
        let remainder = referenceTime.truncatingRemainder(dividingBy: period)
        let progress = (remainder >= 0 ? remainder : remainder + period) / period
        if state == .attention {
            switch progress {
            case 0..<0.15: return progress / 0.15
            case 0.15..<0.55: return 1
            case 0.55..<0.70: return 1 - (progress - 0.55) / 0.15
            default: return 0
            }
        }
        return (1 - cos(2 * .pi * progress)) / 2
    }
}
