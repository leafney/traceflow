import Foundation

public enum HUDTitleTransitionStyle: Sendable, Equatable {
    case none
    case slide
    case fade
}

public enum HUDTitleTransition {
    public static let maximumDuration: TimeInterval = 0.20

    public static func style(shouldAnimate: Bool, reduceMotion: Bool) -> HUDTitleTransitionStyle {
        guard shouldAnimate else { return .none }
        return reduceMotion ? .fade : .slide
    }
}
