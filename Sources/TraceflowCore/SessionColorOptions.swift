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
}
