import CoreGraphics
import Foundation

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
        layout == .horizontal ? CGSize(width: 420, height: 40) : CGSize(width: 40, height: 420)
    }

    public static func defaultFrame(for layout: HUDLayoutMode, visible: CGRect) -> CGRect {
        let size = size(for: layout)
        let origin: CGPoint
        switch layout {
        case .horizontal:
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12)
        case .vertical:
            origin = CGPoint(x: visible.maxX - size.width - 12, y: visible.midY - size.height / 2)
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

public final class HUDPositionStore {
    public static let horizontalKey = "hudPositionHorizontalV3"
    public static let verticalKey = "hudPositionVerticalV1"
    public static let legacyKey = "hudPositionV2"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load(_ layout: HUDLayoutMode) -> HUDPositionRecord? {
        let key = Self.key(for: layout)
        if let data = defaults.data(forKey: key) {
            return try? JSONDecoder().decode(HUDPositionRecord.self, from: data)
        }
        guard layout == .horizontal,
              let data = defaults.data(forKey: Self.legacyKey),
              let record = try? JSONDecoder().decode(HUDPositionRecord.self, from: data) else { return nil }
        save(record, for: .horizontal)
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
