import AppKit
import SwiftUI
import TraceflowCore

struct SessionDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}

struct SessionMarkerView: View {
    let colorHex: String?
    var body: some View {
        SessionDiamond().fill(Color(nsColor: Self.nsColor(colorHex)))
            .frame(width: HUDMetrics.markerDiameter, height: HUDMetrics.markerDiameter)
            .accessibilityHidden(true)
    }

    static func nsColor(_ hex: String?) -> NSColor {
        let rgb = SessionMarkerColor.rgb(hex) ?? (red: 128, green: 128, blue: 128)
        return NSColor(srgbRed: Double(rgb.red) / 255, green: Double(rgb.green) / 255,
                       blue: Double(rgb.blue) / 255, alpha: 1)
    }
}
