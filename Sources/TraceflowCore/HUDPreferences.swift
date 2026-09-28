import Foundation
import CoreFoundation

public enum HUDLayoutMode: String, CaseIterable, Identifiable, Sendable {
    case horizontal
    case vertical

    public var id: String { rawValue }
}

public enum HUDGlowMode: String, CaseIterable, Identifiable, Sendable {
    case standard
    case strong

    public var id: String { rawValue }
}

public final class HUDPreferences {
    public static let layoutKey = "hudLayoutMode"
    public static let glowKey = "hudGlowMode"
    public static let legacyGlowKey = "glowStrength"
    public static let transparencyKey = "hudBackgroundTransparency"
    public static let pinnedKey = "hudPinned"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func loadLayoutMode() -> HUDLayoutMode {
        let mode = defaults.string(forKey: Self.layoutKey).flatMap(HUDLayoutMode.init(rawValue:)) ?? .horizontal
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
