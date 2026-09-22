import CoreGraphics
import Foundation

public enum HUDMetrics {
    public static let longAxis: CGFloat = 420
    public static let shortAxis: CGFloat = 40
    public static let iconLength: CGFloat = 40
    public static let titleLength: CGFloat = 275
    public static let titleTextLength: CGFloat = 263
    public static let lightAreaLength: CGFloat = 104
    public static let lightDiameter: CGFloat = 26
    public static let lightSpacing: CGFloat = 6
    public static let separatorThickness: CGFloat = 0.5
    public static let edgeOffset: CGFloat = 12
}

public struct HUDPositionRecord: Codable, Equatable {
    public let version: Int
    public let displayUUID: String?
    public let legacyDisplayID: UInt32?
    public let displayName: String?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let relativeX: Double
    public let relativeY: Double

    enum CodingKeys: String, CodingKey {
        case version, displayUUID, displayName, pixelWidth, pixelHeight, relativeX, relativeY
        case legacyDisplayID = "displayID"
    }

    public init(version: Int, displayUUID: String?, legacyDisplayID: UInt32?, displayName: String?, pixelWidth: Int?, pixelHeight: Int?, relativeX: Double, relativeY: Double) {
        self.version = version
        self.displayUUID = displayUUID
        self.legacyDisplayID = legacyDisplayID
        self.displayName = displayName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.relativeX = relativeX
        self.relativeY = relativeY
    }
}

public struct HUDScreenIdentity: Equatable {
    public let uuid: String?
    public let displayID: UInt32?
    public let name: String
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(uuid: String?, displayID: UInt32?, name: String, pixelWidth: Int, pixelHeight: Int) {
        self.uuid = uuid
        self.displayID = displayID
        self.name = name
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public enum HUDPositionGeometry {
    public static func matchingScreen(for position: HUDPositionRecord, among screens: [HUDScreenIdentity]) -> Int? {
        if let uuid = position.displayUUID,
           let index = screens.firstIndex(where: { $0.uuid == uuid }) { return index }
        if let id = position.legacyDisplayID,
           let index = screens.firstIndex(where: { $0.displayID == id }) { return index }
        if let name = position.displayName,
           let width = position.pixelWidth, let height = position.pixelHeight,
           let index = screens.firstIndex(where: { $0.name == name && $0.pixelWidth == width && $0.pixelHeight == height }) { return index }
        if let name = position.displayName {
            return screens.firstIndex(where: { $0.name == name })
        }
        return nil
    }

    public static func size(for layout: HUDLayoutMode) -> CGSize {
        layout == .horizontal
            ? CGSize(width: HUDMetrics.longAxis, height: HUDMetrics.shortAxis)
            : CGSize(width: HUDMetrics.shortAxis, height: HUDMetrics.longAxis)
    }

    public static func defaultFrame(for layout: HUDLayoutMode, visible: CGRect) -> CGRect {
        let size = size(for: layout)
        let origin: CGPoint
        switch layout {
        case .horizontal:
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - HUDMetrics.edgeOffset)
        case .vertical:
            origin = CGPoint(x: visible.maxX - size.width - HUDMetrics.edgeOffset, y: visible.midY - size.height / 2)
        }
        return clamped(CGRect(origin: origin, size: size), to: visible)
    }

    public static func clamped(_ frame: CGRect, to visible: CGRect) -> CGRect {
        CGRect(
            x: min(max(visible.minX, frame.minX), max(visible.minX, visible.maxX - frame.width)),
            y: min(max(visible.minY, frame.minY), max(visible.minY, visible.maxY - frame.height)),
            width: frame.width,
            height: frame.height
        )
    }

    public static func relativePosition(of frame: CGRect, in visible: CGRect) -> (x: Double, y: Double) {
        let x = (frame.minX - visible.minX) / max(1, visible.width - frame.width)
        let y = (frame.minY - visible.minY) / max(1, visible.height - frame.height)
        return (clamp(x), clamp(y))
    }

    public static func restoredFrame(for layout: HUDLayoutMode, relativeX: Double, relativeY: Double, visible: CGRect) -> CGRect {
        let size = size(for: layout)
        let frame = CGRect(
            x: visible.minX + max(0, visible.width - size.width) * clamp(relativeX),
            y: visible.minY + max(0, visible.height - size.height) * clamp(relativeY),
            width: size.width,
            height: size.height
        )
        return clamped(frame, to: visible)
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

public enum HUDLayoutTransitionStep: Equatable {
    case save(HUDLayoutMode)
    case resize(HUDLayoutMode, CGSize)
    case restore(HUDLayoutMode)
}

public enum HUDLayoutTransitionPlanner {
    public static func steps(from oldLayout: HUDLayoutMode, to newLayout: HUDLayoutMode) -> [HUDLayoutTransitionStep] {
        guard oldLayout != newLayout else { return [] }
        return [
            .save(oldLayout),
            .resize(newLayout, HUDPositionGeometry.size(for: newLayout)),
            .restore(newLayout)
        ]
    }
}

public enum HUDPositionLoadResult: Equatable {
    case missing
    case loaded(HUDPositionRecord)
    case corrupted
}

public final class HUDPositionStore {
    public static let horizontalKey = "hudPositionHorizontalV3"
    public static let verticalKey = "hudPositionVerticalV1"
    public static let legacyKey = "hudPositionV2"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func loadResult(_ layout: HUDLayoutMode) -> HUDPositionLoadResult {
        let key = Self.key(for: layout)
        if let storedValue = defaults.object(forKey: key) {
            guard let data = storedValue as? Data else { return .corrupted }
            guard let record = try? JSONDecoder().decode(HUDPositionRecord.self, from: data) else { return .corrupted }
            return .loaded(record)
        }
        guard layout == .horizontal, let legacyValue = defaults.object(forKey: Self.legacyKey) else { return .missing }
        guard let data = legacyValue as? Data,
              let record = try? JSONDecoder().decode(HUDPositionRecord.self, from: data) else { return .corrupted }
        save(record, for: .horizontal)
        return .loaded(record)
    }

    public func load(_ layout: HUDLayoutMode) -> HUDPositionRecord? {
        guard case let .loaded(record) = loadResult(layout) else { return nil }
        return record
    }

    public func save(_ record: HUDPositionRecord, for layout: HUDLayoutMode) {
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: Self.key(for: layout))
        }
    }

    public static func key(for layout: HUDLayoutMode) -> String {
        layout == .horizontal ? horizontalKey : verticalKey
    }
}
