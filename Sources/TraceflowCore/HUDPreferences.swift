import Foundation
import CoreFoundation

public enum HUDDisplayStyle: String, CaseIterable, Identifiable, Sendable {
    case standard, medium, compact
    public var id: String { rawValue }
    public var menuTitle: String {
        switch self { case .standard: "标准"; case .medium: "适中"; case .compact: "精简" }
    }
}

public enum HUDRegion: String, Identifiable, Sendable {
    case icon, title, lights
    public var id: String { rawValue }
}

public enum HUDLayoutMode: String, CaseIterable, Identifiable, Sendable {
    case horizontalLeft
    case horizontalRight
    case verticalTop
    case verticalBottom

    public var id: String { rawValue }
    public var isHorizontal: Bool { self == .horizontalLeft || self == .horizontalRight }
    public var lightsAtLeadingEdge: Bool { self == .horizontalLeft || self == .verticalTop }
    public var regions: [HUDRegion] { lightsAtLeadingEdge ? [.lights, .title, .icon] : [.icon, .title, .lights] }
    public var menuTitle: String {
        switch self {
        case .horizontalLeft: "横向左"
        case .horizontalRight: "横向右"
        case .verticalTop: "竖向上"
        case .verticalBottom: "竖向下"
        }
    }
    public var sourceLayout: Self? {
        switch self {
        case .horizontalLeft: .horizontalRight
        case .verticalTop: .verticalBottom
        case .horizontalRight, .verticalBottom: nil
        }
    }
}

public enum HUDIconVisibilityMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case alwaysShow
    case alwaysHide

    public var id: String { rawValue }
}

public enum HUDGlowMode: String, CaseIterable, Identifiable, Sendable {
    case standard
    case strong

    public var id: String { rawValue }
}

public enum HUDTitleColor: String, CaseIterable, Identifiable, Sendable {
    case black
    case white

    public var id: String { rawValue }
}

public final class HUDPreferences {
    public static let displayStyleKey = "hudDisplayStyle"
    public static let layoutKey = "hudLayoutMode"
    public static let glowKey = "hudGlowMode"
    public static let legacyGlowKey = "glowStrength"
    public static let transparencyKey = "hudBackgroundTransparency"
    public static let pinnedKey = "hudPinned"
    public static let titleColorKey = "hudTitleColor"
    public static let iconVisibilityKey = "hudIconVisibilityMode"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func loadDisplayStyle() -> HUDDisplayStyle {
        defaults.string(forKey: Self.displayStyleKey).flatMap(HUDDisplayStyle.init(rawValue:)) ?? .standard
    }

    public func saveDisplayStyle(_ style: HUDDisplayStyle) {
        defaults.set(style.rawValue, forKey: Self.displayStyleKey)
    }

    public func loadLayoutMode() -> HUDLayoutMode {
        let stored = defaults.string(forKey: Self.layoutKey)
        let mode: HUDLayoutMode
        switch stored {
        case "horizontal": mode = .horizontalRight
        case "vertical": mode = .verticalBottom
        default: mode = stored.flatMap(HUDLayoutMode.init(rawValue:)) ?? .horizontalRight
        }
        defaults.set(mode.rawValue, forKey: Self.layoutKey)
        return mode
    }

    public func saveLayoutMode(_ mode: HUDLayoutMode) {
        defaults.set(mode.rawValue, forKey: Self.layoutKey)
    }

    public func loadGlowMode() -> HUDGlowMode {
        if let storedValue = defaults.object(forKey: Self.glowKey) {
            let mode = (storedValue as? String).flatMap(HUDGlowMode.init(rawValue:)) ?? .standard
            defaults.set(mode.rawValue, forKey: Self.glowKey)
            return mode
        }

        let mode: HUDGlowMode
        if let legacyValue = legacyGlowValue() {
            mode = legacyValue == 2 ? .strong : .standard
        } else {
            mode = .standard
        }
        defaults.set(mode.rawValue, forKey: Self.glowKey)
        return mode
    }

    public func saveGlowMode(_ mode: HUDGlowMode) {
        defaults.set(mode.rawValue, forKey: Self.glowKey)
    }

    public func loadTransparency() -> Int {
        guard let number = defaults.object(forKey: Self.transparencyKey) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return HUDBackgroundAppearance.defaultTransparency }
        return HUDBackgroundAppearance.normalize(number.doubleValue)
    }

    public func saveTransparency(_ value: Int) {
        defaults.set(HUDBackgroundAppearance.normalize(Double(value)), forKey: Self.transparencyKey)
    }

    public func loadIconVisibilityMode() -> HUDIconVisibilityMode {
        defaults.string(forKey: Self.iconVisibilityKey).flatMap(HUDIconVisibilityMode.init(rawValue:)) ?? .automatic
    }

    public func saveIconVisibilityMode(_ mode: HUDIconVisibilityMode) {
        defaults.set(mode.rawValue, forKey: Self.iconVisibilityKey)
    }

    public func loadTitleColor() -> HUDTitleColor {
        guard let rawValue = defaults.object(forKey: Self.titleColorKey) as? String else { return .black }
        return HUDTitleColor(rawValue: rawValue) ?? .black
    }

    public func saveTitleColor(_ color: HUDTitleColor) {
        defaults.set(color.rawValue, forKey: Self.titleColorKey)
    }

    public func loadPinned() -> Bool {
        guard let number = defaults.object(forKey: Self.pinnedKey) as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }

    public func savePinned(_ pinned: Bool) {
        defaults.removeObject(forKey: Self.pinnedKey)
        defaults.set(pinned, forKey: Self.pinnedKey)
    }

    private func legacyGlowValue() -> Int? {
        guard let number = defaults.object(forKey: Self.legacyGlowKey) as? NSNumber else { return nil }
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.intValue
        guard (0...2).contains(value), number.doubleValue == Double(value) else { return nil }
        return value
    }
}
