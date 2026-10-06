import Foundation
import CoreGraphics

public struct HUDBackgroundAppearance {
    public static let defaultTransparency = 10
    public let transparency: Int
    public let iconVisibilityMode: HUDIconVisibilityMode
    public init(_ value: Int, iconVisibilityMode: HUDIconVisibilityMode = .automatic) {
        transparency = Self.normalize(Double(value))
        self.iconVisibilityMode = iconVisibilityMode
    }
    public static func normalize(_ value: Double) -> Int {
        guard value.isFinite else { return defaultTransparency }
        return Int(min(100, max(0, value)).rounded())
    }
    public static let iconHiddenThreshold = 80
    public var compact: Bool {
        switch iconVisibilityMode {
        case .automatic: transparency >= Self.iconHiddenThreshold
        case .alwaysShow: false
        case .alwaysHide: true
        }
    }
    public var backgroundAlpha: Double { 1 - Double(transparency) / 100 }
    public var materialAlpha: Double { Double(transparency) / 100 }
    public func size(_ layout: HUDLayoutMode) -> CGSize {
        let length: CGFloat = compact ? 380 : 420
        return layout.isHorizontal ? CGSize(width: length, height: 40) : CGSize(width: 40, height: length)
    }
    public func displayFrame(_ reference: CGRect, layout: HUDLayoutMode) -> CGRect {
        let offset: CGFloat = compact ? 40 : 0
        return CGRect(origin: CGPoint(x: reference.minX + (layout == .horizontalRight ? offset : 0),
                                      y: reference.minY + (layout == .verticalTop ? offset : 0)), size: size(layout))
    }
    public static func referenceFrame(_ display: CGRect, layout: HUDLayoutMode) -> CGRect {
        CGRect(x: layout == .horizontalRight ? display.maxX - 420 : display.minX,
               y: layout == .verticalTop ? display.maxY - 420 : display.minY,
               width: layout.isHorizontal ? 420 : 40,
               height: layout.isHorizontal ? 40 : 420)
    }
}

/// A transition samples from its current visible frame when interrupted.
public struct HUDSizeTransition {
    public let start: CGRect
    public let target: CGRect
    public let initialIconFraction: Double
    public let targetIconFraction: Double
    public static let duration: Double = 0.2
    public let activeDuration: Double
    private let initialProgressTangent: Double

    public init(start: CGRect, target: CGRect, initialIconFraction: Double, targetIconFraction: Double,
                initialIconVelocity: Double = 0) {
        self.start = start
        self.target = target
        self.initialIconFraction = initialIconFraction
        self.targetIconFraction = targetIconFraction
        let distance = abs(targetIconFraction - initialIconFraction)
        activeDuration = Self.duration * (distance == 0 ? 1 : max(0.25, distance))
        let delta = targetIconFraction - initialIconFraction
        initialProgressTangent = delta == 0 || !initialIconVelocity.isFinite ? 0 : initialIconVelocity * activeDuration / delta
    }

    public func sample(elapsed: Double, reduceMotion: Bool = false) -> (frame: CGRect, iconFraction: Double, complete: Bool) {
        let state = progress(elapsed: reduceMotion ? activeDuration : elapsed)
        let eased = state.value
        return (CGRect(x: start.minX + (target.minX - start.minX) * eased,
                       y: start.minY + (target.minY - start.minY) * eased,
                       width: start.width + (target.width - start.width) * eased,
                       height: start.height + (target.height - start.height) * eased),
                initialIconFraction + (targetIconFraction - initialIconFraction) * eased, state.complete)
    }

    /// Velocity of the last rendered sample, carried into an interrupted transition.
    public func iconVelocity(elapsed: Double) -> Double {
        (targetIconFraction - initialIconFraction) * progress(elapsed: elapsed).velocity
    }

    private func progress(elapsed: Double) -> (value: Double, velocity: Double, complete: Bool) {
        let p = min(1, max(0, elapsed / activeDuration))
        // Cubic Hermite: inherit starting velocity and arrive at rest. A reversal
        // first brakes the previous motion instead of stopping for a new ease-in.
        let value = p * p * (3 - 2 * p) + initialProgressTangent * p * (1 - p) * (1 - p)
        let delta = targetIconFraction - initialIconFraction
        var bounded = value
        if delta != 0 {
            let atZero = -initialIconFraction / delta
            let atOne = (1 - initialIconFraction) / delta
            bounded = min(max(atZero, atOne), max(min(atZero, atOne), value))
        }
        let velocity = p >= 1 || value != bounded ? 0
            : (6 * p * (1 - p) + initialProgressTangent * (1 - 4 * p + 3 * p * p)) / activeDuration
        return (bounded, velocity, p >= 1)
    }
}
