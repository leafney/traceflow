import AppKit
import XCTest
import TraceflowCore
@testable import TraceflowApp

/// Normal screen capture. Never forces the tested hosting view to draw.
@MainActor
final class HUDScreenFixture {
    let backdrop: NSWindow
    let origin: NSPoint
    let screen: NSScreen

    init(color: NSColor, screen requestedScreen: NSScreen? = nil) throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("缺少屏幕录制权限：屏幕项跳过，待人工实屏验收")
        }
        let screen = try XCTUnwrap(requestedScreen ?? NSScreen.main)
        self.screen = screen
        let frame = NSRect(x: screen.visibleFrame.midX - 260, y: screen.visibleFrame.midY - 260,
                           width: 520, height: 520)
        backdrop = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.backgroundColor = color
        backdrop.isOpaque = true
        backdrop.hasShadow = false
        backdrop.level = .floating
        origin = NSPoint(x: frame.minX + 40, y: frame.minY + 40)
        backdrop.orderFrontRegardless()
    }

    func close() { backdrop.orderOut(nil) }

    /// Seed every layout before the tested window exists. Production position
    /// restoration can then run without a test moving it after the layout event.
    func preparePositions(defaults: UserDefaults) throws {
        let id = try XCTUnwrap((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value)
        let uuid = try XCTUnwrap(CGDisplayCreateUUIDFromDisplayID(id)).takeRetainedValue()
        let store = HUDPositionStore(defaults: defaults)
        for layout in HUDLayoutMode.allCases {
            let frame = NSRect(origin: origin, size: HUDPositionGeometry.size(for: layout))
            let relative = HUDPositionGeometry.relativePosition(of: frame, in: screen.visibleFrame)
            store.save(HUDPositionRecord(
                version: 3, displayUUID: CFUUIDCreateString(nil, uuid) as String,
                legacyDisplayID: id, displayName: screen.localizedName,
                pixelWidth: Int(screen.frame.width * screen.backingScaleFactor),
                pixelHeight: Int(screen.frame.height * screen.backingScaleFactor),
                relativeX: relative.x, relativeY: relative.y
            ), for: layout)
        }
    }

    func place(_ panel: NSWindow) {
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    func captureNow(_ panel: NSWindow) throws -> HUDScreenPixels {
        let frame = panel.frame
        let primary = try XCTUnwrap(NSScreen.screens.first)
        let rect = CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY,
                          width: frame.width, height: frame.height)
        // Capture WindowServer composition synchronously, avoiding subprocess
        // startup latency. This never asks the hosting view to redraw.
        let image = try XCTUnwrap(CGWindowListCreateImage(rect, .optionOnScreenOnly,
                                                        kCGNullWindowID, [.boundsIgnoreFraming, .bestResolution]))
        return try HUDScreenPixels(image: image)
    }

    func capture(_ panel: NSWindow, fixture: SessionIntegrationFixture) async throws -> HUDScreenPixels {
        try captureNow(panel)
    }

    /// Capture the tested panel first, then compare a fresh panel on the same backdrop.
    func assertSettled(_ controller: HUDPanelController, fixture: SessionIntegrationFixture,
                       regions: [NSRect] = [], compareFull: Bool = true,
                       file: StaticString = #filePath, line: UInt = #line) async throws {
        let panel = try XCTUnwrap(controller.window)
        let began = ProcessInfo.processInfo.systemUptime
        try await Task.sleep(nanoseconds: 300_000_000)
        let testedFrame = panel.frame
        XCTAssertTrue(backdrop.frame.contains(testedFrame), "必须在事件前准备受控背景，不能在采样前移动浮窗", file: file, line: line)
        let early = try await capture(panel, fixture: fixture)
        let remaining = max(0, 1 - (ProcessInfo.processInfo.systemUptime - began))
        try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        let persistent = try await capture(panel, fixture: fixture)
        let frame = panel.frame
        XCTAssertEqual(frame, testedFrame, "稳定帧采样期间窗口不能移动", file: file, line: line)
        panel.orderOut(nil)
        defer { panel.setFrame(frame, display: false); panel.orderFrontRegardless() }
        let reference = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { reference.hide() }
        let clean = try XCTUnwrap(reference.window)
        clean.setFrame(frame, display: false)
        clean.orderFrontRegardless()
        try await Task.sleep(nanoseconds: 300_000_000)
        let expected = try await capture(clean, fixture: fixture)
        try await Task.sleep(nanoseconds: 300_000_000)
        let calibration = try await capture(clean, fixture: fixture)
        // Reference noise must itself meet the bound; never silently widen tolerance.
        expected.assertSimilar(to: calibration, points: frame.size, regions: regions, compareFull: compareFull, file: file, line: line)
        early.assertSimilar(to: expected, points: frame.size, regions: regions, compareFull: compareFull, file: file, line: line)
        persistent.assertSimilar(to: expected, points: frame.size, regions: regions, compareFull: compareFull, file: file, line: line)
    }
}

struct HUDScreenPixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(image: CGImage) throws {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw NSError(domain: "HUDPixels", code: 1) }
        self.width = width
        self.height = height
        bytes = pixels
    }

    func assertSimilar(to reference: Self, points: NSSize, regions: [NSRect], compareFull: Bool = true,
                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(width, reference.width, file: file, line: line)
        XCTAssertEqual(height, reference.height, file: file, line: line)
        guard width == reference.width, height == reference.height else { return }
        let scaleX = CGFloat(width) / points.width
        let scaleY = CGFloat(height) / points.height
        let full = NSRect(origin: .zero, size: points)
        for region in (compareFull ? [full] : []) + regions {
            let rect = region.intersection(full)
            guard !rect.isEmpty else { continue }
            var changed = 0, count = 0, sum = 0
            for y in max(0, Int(rect.minY * scaleY))..<min(height, Int(ceil(rect.maxY * scaleY))) {
                for x in max(0, Int(rect.minX * scaleX))..<min(width, Int(ceil(rect.maxX * scaleX))) {
                    let index = (y * width + x) * 4
                    var differs = false
                    for channel in 0..<3 {
                        let delta = abs(Int(bytes[index + channel]) - Int(reference.bytes[index + channel]))
                        sum += delta
                        differs = differs || delta > 8
                    }
                    changed += differs ? 1 : 0
                    count += 1
                }
            }
            guard count > 0 else { continue }
            XCTAssertLessThanOrEqual(Double(changed) / Double(count), 0.005,
                                     "旧内容区域像素差异过大：\(rect)", file: file, line: line)
            XCTAssertLessThanOrEqual(Double(sum) / Double(count * 3), 1.5,
                                     "旧内容区域平均差异过大：\(rect)", file: file, line: line)
        }
    }

}
