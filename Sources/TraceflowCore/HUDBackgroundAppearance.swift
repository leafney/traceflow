import Foundation
import CoreGraphics

public struct HUDBackgroundAppearance {
    public static let defaultTransparency = 10
    public let transparency: Int
    public init(_ value: Int) { transparency = Self.normalize(Double(value)) }
    public static func normalize(_ value: Double) -> Int {
        guard value.isFinite else { return defaultTransparency }
        return Int(min(100, max(0, value)).rounded())
    }
    public static let iconHiddenThreshold = 80
    public var compact: Bool { transparency >= Self.iconHiddenThreshold }
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

    public init(start: CGRect, target: CGRect, initialIconFraction: Double, targetIconFraction: Double) {
        self.start = start
        self.target = target
        self.initialIconFraction = initialIconFraction
        self.targetIconFraction = targetIconFraction
    }

    public func sample(elapsed: Double, reduceMotion: Bool = false) -> (frame: CGRect, iconFraction: Double, complete: Bool) {
        let progress = reduceMotion ? 1 : min(1, max(0, elapsed / Self.duration))
        let eased = progress * progress * (3 - 2 * progress)
        return (CGRect(x: start.minX + (target.minX - start.minX) * eased,
                       y: start.minY + (target.minY - start.minY) * eased,
                       width: start.width + (target.width - start.width) * eased,
                       height: start.height + (target.height - start.height) * eased),
                initialIconFraction + (targetIconFraction - initialIconFraction) * eased, progress >= 1)
    }
}
