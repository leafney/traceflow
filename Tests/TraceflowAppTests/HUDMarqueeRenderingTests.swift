import AppKit
import CoreText
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

    func testUprightGlyphsMatchUnclippedReferenceInNormalAndReducedMotion() throws {
        // Compare a full upright glyph with a larger, unclipped Core Text reference at 4x resolution.
        for scale in [CGFloat(1), 2] {
            for title in ["🙂", "👨‍👩‍👧‍👦", "修", "！", "∫"] {
                let layout = HUDTitleTextLayout(title: title, vertical: true, backingScale: scale)
                let run = try XCTUnwrap(layout.runs.first)
                let line = try XCTUnwrap(run.line)
                let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                let baseline = title == "修" ? max(layout.font.ascender, ink.maxY + 1 / scale) : ink.maxY + 1 / scale
                let expected = try renderLargeCanvas { context in
                    context.translateBy(x: 20 - ink.midX, y: baseline)
                    context.scaleBy(x: 1, y: -1)
                    context.textMatrix = .identity
                    context.textPosition = .zero
                    CTLineDraw(line, context)
                }
                XCTAssertGreaterThan(expected.filter { $0 != 0 }.count, 20)
                for reduced in [false, true] {
                    let actual = try renderLargeCanvas { context in
                        layout.draw(in: context, offset: 0, color: .black, reduceMotion: reduced)
                    }
                    XCTAssertEqual(actual, expected, "首个完整字形不能被标题窗口裁剪：\(title)，屏幕缩放 \(scale)")
                }
                XCTAssertGreaterThanOrEqual(run.baselineOffset - ink.maxY * run.scale, 0)
                XCTAssertLessThanOrEqual(run.baselineOffset - ink.minY * run.scale, run.advance)
            }
        }
    }

    func testEmojiAtLongTitleStartAndEndHasSameCompleteInk() throws {
        let glyph = HUDTitleTextLayout(title: "🙂", vertical: true)
        let shortPixels = try render(glyph, offset: 0)
        let long = HUDTitleTextLayout(title: String(repeating: "🙂", count: 8), vertical: true)
        XCTAssertGreaterThan(long.length, 88)
        let prefix = long.runs.dropLast().reduce(CGFloat(0)) { $0 + $1.advance }
        // At the last glyph's start, the remaining window contains that glyph and part of the next copy.
        let lastPixels = try render(long, offset: -prefix)
        let firstPixels = try render(long, offset: 0)
        let width = 40
        let run = try XCTUnwrap(glyph.runs.first)
        let glyphRows = Int(ceil(run.baselineOffset - run.inkBounds.minY * run.scale))
        for row in 0..<glyphRows {
            // The bitmap bytes follow the flipped view's top-to-bottom output.
            let start = row * width * 4
            let end = start + width * 4
            XCTAssertTrue(Array(firstPixels[start..<end]) == Array(shortPixels[start..<end]), "首字形第 \(row) 行与完整参考不同")
            XCTAssertTrue(Array(lastPixels[start..<end]) == Array(shortPixels[start..<end]), "末字形第 \(row) 行与完整参考不同")
        }
    }

    private func renderLargeCanvas(_ draw: (CGContext) -> Void) throws -> [UInt8] {
        let factor = 4
        let width = 72 * factor, height = 120 * factor
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                   colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(factor), y: -CGFloat(factor))
        context.translateBy(x: 16, y: 16)
        context.setFillColor(NSColor.black.cgColor)
        draw(context)
        graphics.flushGraphics()
        return Array(UnsafeBufferPointer(start: try XCTUnwrap(bitmap.bitmapData), count: width * height * 4))
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
