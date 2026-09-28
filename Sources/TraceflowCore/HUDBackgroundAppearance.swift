import Foundation
import CoreGraphics

public struct HUDBackgroundAppearance {
    public let transparency: Int
    public init(_ value: Int) { transparency = Self.normalize(Double(value)) }
    public static func normalize(_ value: Double) -> Int {
        guard value.isFinite else { return 80 }
        return Int(min(100, max(0, value)).rounded())
    }
    public var compact: Bool { transparency >= 90 }
    public var backgroundAlpha: Double { 1 - Double(transparency) / 100 }
    public var materialAlpha: Double { Double(transparency) / 100 }
    public func size(_ layout: HUDLayoutMode) -> CGSize {
        let length: CGFloat = compact ? 380 : 420
        return layout == .horizontal ? CGSize(width: length, height: 40) : CGSize(width: 40, height: length)
    }
    public func displayFrame(_ reference: CGRect, layout: HUDLayoutMode) -> CGRect {
        CGRect(origin: CGPoint(x: reference.minX + (layout == .horizontal && compact ? 40 : 0), y: reference.minY), size: size(layout))
    }
    public static func referenceFrame(_ display: CGRect, layout: HUDLayoutMode) -> CGRect {
        CGRect(x: layout == .horizontal ? display.maxX - 420 : display.minX,
               y: display.minY, width: layout == .horizontal ? 420 : 40,
               height: layout == .horizontal ? 40 : 420)
    }
}
