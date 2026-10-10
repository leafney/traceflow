import AppKit
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class HUDMarqueeRenderingTests: XCTestCase {
    func testFullLayoutAndCycleBoundaryRenderContinuouslyInBothDirections() throws {
        for vertical in [false, true] {
            let layout = HUDTitleTextLayout(title: "修复 login 状态 2026 🙂！very_long_session_title", vertical: vertical)
            XCTAssertGreaterThan(layout.length, 88)
            let initial = try render(layout, offset: 0)
            let wrapped = try render(layout, offset: -(layout.length + 24))
            XCTAssertEqual(initial, wrapped)
            XCTAssertNotEqual(initial, try render(layout, offset: -40))
            XCTAssertGreaterThan(initial.filter { $0 != 0 }.count, 20)
            let reduced = try render(layout, offset: -40, reduceMotion: true)
            XCTAssertEqual(reduced, try render(layout, offset: 0, reduceMotion: true))
        }
    }

    func testShortTitleDoesNotMoveAndColorUpdatesDoNotRebuildLayout() throws {
        for vertical in [false, true] {
            let view = HUDMarqueeNSView(title: "短", vertical: vertical, color: .black)
            let layout = view.textLayout
            XCTAssertLessThan(layout.length, 88)
            view.configure(title: "短", vertical: vertical, color: .white)
            XCTAssertTrue(layout === view.textLayout)
            XCTAssertEqual(try render(layout, offset: 0), try render(layout, offset: -40))
        }
    }

    func testExportDeterministicVisualSamplesWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["TRACEFLOW_MARQUEE_ARTIFACT"] else { return }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 720, pixelsHigh: 440,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                   colorSpaceName: .deviceRGB, bytesPerRow: 720 * 4, bitsPerPixel: 32))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }
        let context = graphics.cgContext
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 720, height: 440))
        context.translateBy(x: 0, y: 440)
        context.scaleBy(x: 1, y: -1)
        let title = "修复 login 状态🙂！2026"
        for vertical in [false, true] {
            let layout = HUDTitleTextLayout(title: title, vertical: vertical)
            for (index, offset) in [CGFloat(0), -40, -(layout.length + 24) + 10].enumerated() {
                context.saveGState()
                context.translateBy(x: vertical ? CGFloat(360 + index * 110) : 30,
                                    y: vertical ? 30 : CGFloat(30 + index * 125))
                context.scaleBy(x: 2, y: 2)
                context.setFillColor(NSColor(calibratedWhite: 0.92, alpha: 1).cgColor)
                context.fill(CGRect(x: 0, y: 0, width: vertical ? 40 : 100, height: vertical ? 100 : 40))
                context.translateBy(x: vertical ? 0 : 6, y: vertical ? 6 : 0)
                layout.draw(in: context, offset: offset, color: .black)
                context.restoreGState()
            }
        }
        graphics.flushGraphics()
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func render(_ layout: HUDTitleTextLayout, offset: CGFloat, reduceMotion: Bool = false) throws -> [UInt8] {
        let width = layout.vertical ? 40 : 88
        let height = layout.vertical ? 88 : 40
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                   colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        layout.draw(in: context, offset: offset, color: .black, reduceMotion: reduceMotion)
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let bytes = try XCTUnwrap(bitmap.bitmapData)
        return Array(UnsafeBufferPointer(start: bytes, count: width * height * 4))
    }
}
