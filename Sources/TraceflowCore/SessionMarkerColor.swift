import Foundation

public enum SessionMarkerColorError: Error {
    case exhausted, invalidColor, missingSession, protectedData, writeFailed
}

public enum SessionMarkerColor {
    public static let placeholder = "#808080"

    public static func normalized(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else { return nil }
        return value.uppercased()
    }

    public static func rgb(_ raw: String?) -> (red: Int, green: Int, blue: Int)? {
        guard let value = normalized(raw), let number = Int(value.dropFirst(), radix: 16) else { return nil }
        return (number >> 16, (number >> 8) & 255, number & 255)
    }

    static let candidates: [String] = {
        var values = ["#477EE8", "#9963DD", "#E458A3", "#D77B23", "#1597A4", "#597344"]
        for hue in 0..<360 {
            for saturation in [0.65, 0.80] {
                for lightness in [0.45, 0.60] {
                    let chroma = (1 - abs(2 * lightness - 1)) * saturation
                    let h = Double(hue) / 60
                    let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
                    let base: (Double, Double, Double)
                    switch h {
                    case ..<1: base = (chroma, x, 0)
                    case ..<2: base = (x, chroma, 0)
                    case ..<3: base = (0, chroma, x)
                    case ..<4: base = (0, x, chroma)
                    case ..<5: base = (x, 0, chroma)
                    default: base = (chroma, 0, x)
                    }
                    let m = lightness - chroma / 2
                    let channels = [base.0, base.1, base.2].map { Int((($0 + m) * 255).rounded()) }
                    values.append(String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2]))
                }
            }
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }()

    public static func allocate(occupied raw: Set<String>) throws -> String {
        let occupied = Set(raw.compactMap(normalized))
        if occupied.isEmpty { return "#477EE8" }
        let channels = occupied.compactMap(rgb)
        var best: String?
        var bestScore = -Double.infinity
        for candidate in candidates where candidate != placeholder && !occupied.contains(candidate) {
            let c = rgb(candidate)!
            let score = channels.map { other in
                0.30 * pow(Double(c.red - other.red), 2)
                    + 0.59 * pow(Double(c.green - other.green), 2)
                    + 0.11 * pow(Double(c.blue - other.blue), 2)
            }.min() ?? 0
            if score > bestScore { best = candidate; bestScore = score }
        }
        if let best { return best }
        return try firstUnused(occupied: occupied)
    }

    // Separate bounded fallback permits testing exhaustion without allocating millions of records.
    static func firstUnused(occupied: Set<String>, upperBound: Int = 0xFFFFFF) throws -> String {
        for number in 0...upperBound where number != 0x808080 {
            let value = String(format: "#%06X", number)
            if !occupied.contains(value) { return value }
        }
        throw SessionMarkerColorError.exhausted
    }

    public static func fillingMissing(in sessions: [PersistedSession]) throws -> [PersistedSession] {
        var result = sessions
        var occupied = Set(sessions.compactMap { normalized($0.markerColorHex) })
        let indices = sessions.indices.sorted {
            let a = sessions[$0], b = sessions[$1]
            return a.rotationIndex == b.rotationIndex ? a.id < b.id : a.rotationIndex < b.rotationIndex
        }
        for index in indices {
            if let color = normalized(result[index].markerColorHex) {
                result[index].markerColorHex = color
            } else {
                let color = try allocate(occupied: occupied)
                result[index].markerColorHex = color
                occupied.insert(color)
            }
        }
        return result
    }
}
