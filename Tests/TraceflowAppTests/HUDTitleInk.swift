import AppKit

/// Title ink in screen coordinates: cross axis grows down for a horizontal
/// title and right for a vertical title. Uses a white backdrop and black text.
struct HUDTitleInk {
    let crossCount = 40
    let longCount = 120
    let values: [Double]

    init(pixels: HUDScreenPixels, points: NSSize, origin: CGFloat, vertical: Bool) {
        var values = [Double](repeating: 0, count: 40 * 120)
        for long in 0..<120 {
            for cross in 1..<39 {
                let px = vertical ? CGFloat(cross) : origin + CGFloat(long)
                let py = vertical ? origin + CGFloat(long) : CGFloat(cross)
                let x = Int(px * CGFloat(pixels.width) / points.width)
                let y = Int(py * CGFloat(pixels.height) / points.height)
                guard x >= 0, x < pixels.width, y >= 0, y < pixels.height else { continue }
                let i = (y * pixels.width + x) * 4
                let darkness = 255 - Double(pixels.bytes[i])
                values[long * 40 + cross] = darkness > 32 ? darkness / 255 : 0
            }
        }
        self.values = values
    }

    init(values: [Double]) {
        precondition(values.count == 40 * 120)
        self.values = values
    }

    struct Motion {
        let outgoingShift: Int
        let outgoingOpacity: Double
        let incomingOffset: Double
        let incomingOpacity: Double
    }

    /// A long outgoing title and a narrow incoming glyph occupy disjoint
    /// long-axis bands. Fit the outgoing layer first, then subtract its pixels
    /// to recover the incoming layer, rather than mistaking any change for motion.
    func motion(from old: Self, to new: Self) -> Motion? {
        var best: (error: Double, shift: Int, alpha: Double)?
        for shift in -39...39 {
            var dot = 0.0, norm = 0.0
            for long in 35..<100 {
                for cross in 1..<39 {
                    let source = cross - shift
                    let value = (0..<40).contains(source) ? old.values[long * 40 + source] : 0
                    dot += value * values[long * 40 + cross]
                    norm += value * value
                }
            }
            guard norm > 0.1 else { continue }
            let alpha = max(0, min(1, dot / norm))
            var error = 0.0
            for long in 35..<100 {
                for cross in 1..<39 {
                    let source = cross - shift
                    let value = (0..<40).contains(source) ? old.values[long * 40 + source] : 0
                    let delta = values[long * 40 + cross] - alpha * value
                    error += delta * delta
                }
            }
            if best == nil || error < best!.error { best = (error, shift, alpha) }
        }
        guard let best, best.alpha > 0.03 else { return nil }
        var incomingMass = 0.0, incomingMoment = 0.0
        var targetMass = 0.0, targetMoment = 0.0
        for long in 0..<12 {
            for cross in 1..<39 {
                let source = cross - best.shift
                let oldValue = (0..<40).contains(source) ? old.values[long * 40 + source] : 0
                let residual = max(0, values[long * 40 + cross] - best.alpha * oldValue)
                incomingMass += residual
                incomingMoment += residual * Double(cross)
                let target = new.values[long * 40 + cross]
                targetMass += target
                targetMoment += target * Double(cross)
            }
        }
        guard incomingMass > 0.05, targetMass > 0.05 else { return nil }
        return Motion(outgoingShift: best.shift, outgoingOpacity: best.alpha,
                      incomingOffset: incomingMoment / incomingMass - targetMoment / targetMass,
                      incomingOpacity: incomingMass / targetMass)
    }
}
