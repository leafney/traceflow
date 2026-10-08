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

    private static let candidateRGB = candidates.map { rgb($0)! }

    /// Keeps max-min scores across a batch. Every newly occupied color updates
    /// each candidate once, rather than recomputing all previous distances.
    private struct Allocator {
        var occupied: Set<String>
        var scores = [Double](repeating: .infinity, count: candidates.count)

        init(occupied: Set<String>) {
            self.occupied = occupied
            for color in occupied { updateScores(with: rgb(color)!) }
        }

        mutating func updateScores(with color: (red: Int, green: Int, blue: Int)) {
            for index in candidates.indices {
                let c = candidateRGB[index]
                let distance = 0.30 * pow(Double(c.red - color.red), 2)
                    + 0.59 * pow(Double(c.green - color.green), 2)
                    + 0.11 * pow(Double(c.blue - color.blue), 2)
                scores[index] = min(scores[index], distance)
            }
        }

        mutating func next() throws -> String {
            var selected: String?
            var bestScore = -Double.infinity
            if occupied.isEmpty {
                selected = "#477EE8"
            } else {
                for index in candidates.indices {
                    let candidate = candidates[index]
                    guard candidate != placeholder, !occupied.contains(candidate) else { continue }
                    if scores[index] > bestScore {
                        selected = candidate
                        bestScore = scores[index]
                    }
                }
            }
            let color = try selected ?? firstUnused(occupied: occupied)
            occupied.insert(color)
            updateScores(with: rgb(color)!)
            return color
        }
    }

    public static func allocate(occupied raw: Set<String>) throws -> String {
        var allocator = Allocator(occupied: Set(raw.compactMap(normalized)))
        return try allocator.next()
    }

    // Separate bounded fallback permits testing exhaustion without allocating millions of records.
    static func firstUnused(occupied: Set<String>, upperBound: Int = 0xFFFFFF) throws -> String {
        for number in 0...upperBound where number != 0x808080 {
            let value = String(format: "#%06X", number)
            if !occupied.contains(value) { return value }
        }
        throw SessionMarkerColorError.exhausted
    }

    public static let historyWindow: TimeInterval = 7 * 24 * 60 * 60

    public static func isHistorical(_ session: PersistedSession, now: Date) -> Bool {
        now.timeIntervalSince(session.lastActivityAt ?? session.lastUpdatedAt) > historyWindow
    }

    public static func fillingMissing(in sessions: [PersistedSession], now: Date) throws -> [PersistedSession] {
        var result = sessions
        var missing: [Int] = []
        var occupied = Set<String>()
        for index in result.indices {
            if isHistorical(result[index], now: now) {
                result[index].markerColorHex = nil
            } else {
                result[index].markerColorHex = normalized(result[index].markerColorHex)
                if let color = result[index].markerColorHex { occupied.insert(color) }
                else { missing.append(index) }
            }
        }
        guard !missing.isEmpty else { return result }
        var allocator = Allocator(occupied: occupied)
        missing.sort {
            let a = sessions[$0], b = sessions[$1]
            return a.rotationIndex == b.rotationIndex ? a.id < b.id : a.rotationIndex < b.rotationIndex
        }
        for index in missing { result[index].markerColorHex = try allocator.next() }
        return result
    }
}
