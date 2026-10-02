import AppKit
import XCTest
import TraceflowCore
@testable import TraceflowApp

/// Normal screen capture. Never forces the tested hosting view to draw.
@MainActor
final class HUDScreenFixture {
    let backdrop: NSWindow
    let origin: NSPoint

    init(color: NSColor, screen requestedScreen: NSScreen? = nil) throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("缺少屏幕录制权限：屏幕项跳过，待人工实屏验收")
        }
        let screen = try XCTUnwrap(requestedScreen ?? NSScreen.main)
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

    func place(_ panel: NSWindow) {
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    func capture(_ panel: NSWindow, fixture: SessionIntegrationFixture) async throws -> HUDScreenPixels {
        let frame = panel.frame
        let primary = try XCTUnwrap(NSScreen.screens.first)
        let file = fixture.root.appendingPathComponent(UUID().uuidString + ".png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // Screen-region capture includes the actual desktop composition.
        process.arguments = ["-x", "-R\(Int(frame.minX)),\(Int(primary.frame.maxY - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))", file.path]
        try process.run()
        try await fixture.waitUntil { !process.isRunning }
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "HUDScreenCapture", code: Int(process.terminationStatus))
        }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: file)))
        return try HUDScreenPixels(image: XCTUnwrap(bitmap.cgImage))
    }

    /// Capture the tested panel first, then compare a fresh panel on the same backdrop.
    func assertSettled(_ controller: HUDPanelController, fixture: SessionIntegrationFixture,
                       regions: [NSRect] = [], placePanel: Bool = true, compareFull: Bool = true,
                       file: StaticString = #filePath, line: UInt = #line) async throws {
        let panel = try XCTUnwrap(controller.window)
        if placePanel { place(panel) }
        let began = ProcessInfo.processInfo.systemUptime
        try await Task.sleep(nanoseconds: 300_000_000)
        let early = try await capture(panel, fixture: fixture)
        let remaining = max(0, 1 - (ProcessInfo.processInfo.systemUptime - began))
        try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        let persistent = try await capture(panel, fixture: fixture)
        let frame = panel.frame
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

    func changedFraction(comparedTo other: Self, points: NSSize, region: NSRect) -> Double {
        guard width == other.width, height == other.height else { return 1 }
        let scaleX = CGFloat(width) / points.width
        let scaleY = CGFloat(height) / points.height
        let rect = region.intersection(NSRect(origin: .zero, size: points))
        guard !rect.isEmpty else { return 0 }
        var changed = 0, count = 0
        for y in max(0, Int(rect.minY * scaleY))..<min(height, Int(ceil(rect.maxY * scaleY))) {
            for x in max(0, Int(rect.minX * scaleX))..<min(width, Int(ceil(rect.maxX * scaleX))) {
                let index = (y * width + x) * 4
                if (0..<3).contains(where: { abs(Int(bytes[index + $0]) - Int(other.bytes[index + $0])) > 8 }) {
                    changed += 1
                }
                count += 1
            }
        }
        return count == 0 ? 0 : Double(changed) / Double(count)
    }
}
