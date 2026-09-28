import AppKit
import XCTest
@testable import TraceflowApp
import TraceflowCore

@MainActor
final class VerticalMixedTitleRenderingTests: XCTestCase {
    func testChangingColorRedrawsTitleAndEllipsis() throws {
        let view = MixedTitleNSView(title: String(repeating: "标题", count: 30), color: .black)
        view.frame = NSRect(x: 0, y: 0, width: 40, height: 80)

        let black = try render(view)
        view.color = .white
        let white = try render(view)
        view.color = .black
        let blackAgain = try render(view)

        XCTAssertGreaterThan(black.coveredPixels, 20)
        XCTAssertGreaterThan(white.coveredPixels, 20)
        XCTAssertLessThan(black.averageBrightness, 0.1)
        XCTAssertGreaterThan(white.averageBrightness, 0.9)
        XCTAssertLessThan(blackAgain.averageBrightness, 0.1)
        XCTAssertGreaterThan(black.bottomCoveredPixels, 0)
        XCTAssertGreaterThan(white.bottomCoveredPixels, 0)
        XCTAssertLessThan(black.bottomBrightness, 0.1)
        XCTAssertGreaterThan(white.bottomBrightness, 0.9)
    }

    private func render(_ view: MixedTitleNSView) throws -> (coveredPixels: Int, bottomCoveredPixels: Int, averageBrightness: Double, bottomBrightness: Double) {
        let width = Int(view.bounds.width)
        let height = Int(view.bounds.height)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        view.draw(view.bounds)
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        var covered = 0
        var bottomCovered = 0
        var brightness = 0.0
        var bottomBrightness = 0.0
        for y in 0..<height {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5 else { continue }
                covered += 1
                let pixelBrightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                if y >= height - 24 {
                    bottomCovered += 1
                    bottomBrightness += pixelBrightness
                }
                brightness += pixelBrightness
            }
        }
        return (covered, bottomCovered, brightness / Double(max(covered, 1)), bottomBrightness / Double(max(bottomCovered, 1)))
    }
}
