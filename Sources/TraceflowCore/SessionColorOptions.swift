import Foundation

public struct SessionColorOption: Equatable, Sendable {
    public let hex: String
    public let isSelected: Bool
}

/// The palette and shuffle are stable across launches; changing either changes saved visual positions.
public enum SessionColorOptions {
    private static let palette = [
        "#477EE8", "#9963DD", "#E458A3", "#D77B23", "#1597A4", "#597344",
        "#6C7FE8", "#E4A665", "#67B7A0", "#E16F7F", "#AC80CF", "#8192A5",
        "#C55D54", "#5587A6", "#A68140", "#598C6C", "#C46182", "#7869B5"
    ]

    public static func options(sessionID: String, currentColor: String?) -> [SessionColorOption] {
        var state: UInt64 = 14695981039346656037
        for byte in sessionID.utf8 {
            state = (state ^ UInt64(byte)) &* 1099511628211
        }
        var colors = palette
        for index in stride(from: colors.count - 1, through: 1, by: -1) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            colors.swapAt(index, Int(state % UInt64(index + 1)))
        }
        colors = Array(colors.prefix(6))
        let current = SessionMarkerColor.normalized(currentColor)
        if let current, !colors.contains(current) { colors[0] = current }
        return colors.map { SessionColorOption(hex: $0, isSelected: $0 == current) }
    }
    /// Select the black or white mark with the greater contrast against the sRGB color.
    public static func usesDarkSelectionMark(for color: String) -> Bool {
        guard let rgb = SessionMarkerColor.rgb(color) else { return false }
        func linear(_ channel: Int) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
    }

}
