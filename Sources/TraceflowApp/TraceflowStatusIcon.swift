import AppKit

@MainActor
enum TraceflowStatusIcon {
    static func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.setShouldAntialias(true)
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: rect.width / 104, y: rect.height / 104)
            context.translateBy(x: -12, y: -12)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)
            context.setLineWidth(5)
            let radii: [Double] = [40, 28, 16]
            for radius in radii {
                context.strokeEllipse(in: CGRect(x: 64 - radius, y: 64 - radius,
                                                  width: radius * 2, height: radius * 2))
            }
            for (ring, radius) in radii.enumerated() {
                let angle = Double(-90 + ring * 120 + ring * 35) * .pi / 180
                let center = CGPoint(x: 64 + radius * cos(angle), y: 64 + radius * sin(angle))
                context.fillEllipse(in: CGRect(x: center.x - 4.3, y: center.y - 4.3, width: 8.6, height: 8.6))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Traceflow"
        return image
    }
}
