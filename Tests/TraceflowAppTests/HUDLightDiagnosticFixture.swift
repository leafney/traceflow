import AppKit
import SwiftUI
import XCTest
import TraceflowCore
@testable import TraceflowApp

/// Diagnostic pixels have a known sRGB, premultiplied RGBA layout. Production
/// CGImage providers need not have that layout, so never read them directly.
struct HUDLightDiagnosticPixels {
    let size: Int
    let scale: Double
    let bytes: [UInt8]

    init(image: CGImage, scale: Double) throws {
        size = image.width
        self.scale = scale
        XCTAssertEqual(image.width, Int(64 * scale))
        XCTAssertEqual(image.height, image.width)
        var data = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw CocoaError(.coderReadCorrupt) }
        bytes = data
    }

    func rgba(x: Int, y: Int, background: Double?) -> [Double] {
        let offset = (y * size + x) * 4
        let alpha = Double(bytes[offset + 3]) / 255
        let rgb = (0..<3).map { Double(bytes[offset + $0]) / 255 + (background ?? 0) * (1 - alpha) }
        return rgb + [alpha]
    }

    func contrast(x: Int, y: Int, background: Double?) -> Double {
        let color = rgba(x: x, y: y, background: background)
        guard let background else { return color[3] }
        return sqrt(color.prefix(3).reduce(0) { $0 + pow($1 - background, 2) } / 3)
    }

    /// Eight actual pixel rays. Deduplicate nearest-pixel samples so 1x cannot
    /// manufacture a two-sample gap by reading the same pixel twice.
    func rays(radius: Double, outer: Double, background: Double?) -> [[(r: Double, contrast: Double, rgba: [Double])]] {
        (0..<8).map { direction in
            let angle = Double(direction) * .pi / 4
            var result: [(Double, Double, [Double])] = []
            var previous = -1
            let lower = max(0, radius - 2)
            for index in 0...Int(ceil((outer + 2 - lower) * scale * 2)) {
                let r = lower + Double(index) / (scale * 2)
                let x = min(size - 1, max(0, Int((32 + cos(angle) * r) * scale)))
                let y = min(size - 1, max(0, Int((32 + sin(angle) * r) * scale)))
                let pixel = y * size + x
                guard pixel != previous else { continue }
                previous = pixel
                let actualRadius = hypot((Double(x) + 0.5) / scale - 32, (Double(y) + 0.5) / scale - 32)
                result.append((actualRadius, contrast(x: x, y: y, background: background), rgba(x: x, y: y, background: background)))
            }
            return result
        }
    }

    /// A band, rather than one AA pixel: contrast drops, stays low for two
    /// distinct samples, then rebounds outside. Natural fade has no rebound.
    func rebound(radius: Double, outer: Double, background: Double?) -> Double {
        rays(radius: radius, outer: outer, background: background).map { ray in
            guard ray.count >= 4 else { return 0 }
            var maximum = 0.0
            for index in 1..<(ray.count - 2) {
                let valley = max(ray[index].contrast, ray[index + 1].contrast)
                let before = ray[..<index].map(\.contrast).max() ?? 0
                let after = ray[(index + 2)...].map(\.contrast).max() ?? 0
                maximum = max(maximum, min(before - valley, after - valley))
            }
            return maximum
        }.max() ?? 0
    }

    func meanDifference(from other: Self, outside radius: Double = 0) -> Double {
        guard size == other.size else { return 1 }
        var sum = 0.0, count = 0
        for y in 0..<size {
            for x in 0..<size {
                let r = hypot((Double(x) + 0.5) / scale - 32, (Double(y) + 0.5) / scale - 32)
                guard r >= radius else { continue }
                for channel in 0..<4 {
                    let offset = (y * size + x) * 4 + channel
                    sum += abs(Double(bytes[offset]) - Double(other.bytes[offset])) / 255
                    count += 1
                }
            }
        }
        return sum / Double(max(1, count))
    }
}

@MainActor
enum HUDLightDiagnosticFixture {
    static let directory = URL(fileURLWithPath: "/private/tmp/traceflow-light-halo-white-ring", isDirectory: true)
    static let progresses = [0.0, 0.02, 0.05, 0.1, 0.25, 0.5, 0.75, 1.0]
    static let sequence = [0.0, 0.25, 0.5, 0.75, 1, 0.75, 0.5, 0.25, 0.1, 0.05, 0.02, 0]

    static func visual(_ q: Double) -> HUDLightVisualParameters {
        HUDLightVisualParameters(scale: 0.9 + 0.2 * q, bodyOpacity: 0.55 + 0.45 * q,
                                 glowIntensity: q, isTimelinePaused: false)
    }

    static func render<V: View>(_ view: V, scale: Double) throws -> (CGImage, HUDLightDiagnosticPixels) {
        let renderer = ImageRenderer(content: view.frame(width: 64, height: 64))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        return (image, try HUDLightDiagnosticPixels(image: image, scale: scale))
    }

    static func save(_ image: CGImage, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(cgImage: image)
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent(name + ".png"))
    }

    static func composite(_ pixels: HUDLightDiagnosticPixels, background: Double) throws -> CGImage {
        var bytes = pixels.bytes
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Double(bytes[offset + 3]) / 255
            for channel in 0..<3 {
                bytes[offset + channel] = UInt8(min(255, max(0, Double(bytes[offset + channel]) + 255 * background * (1 - alpha))).rounded())
            }
            bytes[offset + 3] = 255
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: pixels.size, height: pixels.size, bitsPerComponent: 8,
                                    bitsPerPixel: 32, bytesPerRow: pixels.size * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}

@MainActor
final class HUDLightDiagnosticState: ObservableObject {
    @Published var visual = HUDLightDiagnosticFixture.visual(0)
}

struct HUDLightDiagnosticView: View {
    @ObservedObject var state: HUDLightDiagnosticState
    let kind: StatusLightKind
    let mode: HUDGlowMode
    var body: some View {
        StatusLightFrame(kind: kind, active: true, glow: mode, visual: state.visual)
            .frame(width: 64, height: 64)
    }
}
