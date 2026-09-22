import Foundation

public enum HUDTitleTransitionStyle: Sendable, Equatable {
    case none
    case slide
    case fade
}

public enum HUDTitleTransition {
    public static func style(shouldAnimate: Bool, reduceMotion: Bool) -> HUDTitleTransitionStyle {
        if reduceMotion { return .fade }
        return shouldAnimate ? .slide : .none
    }
}
