import AppKit
import SwiftUI
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class HUDLightDiagnosticTests: XCTestCase {
    private let kinds = [StatusLightKind.attention, .completed, .running]
    private let modes = [HUDGlowMode.standard, .strong]
    private let backgrounds: [Double?] = [nil, 1, 0.85, 0.2]

    @ViewBuilder private func control(_ kind: StatusLightKind, gap: Bool, gradient: Bool) -> some View {
        if gap {
            ZStack {
                Circle().stroke(kind.color.opacity(0.7), lineWidth: 2).frame(width: 34, height: 34)
                Circle().fill(kind.color.opacity(0.7)).frame(width: 24, height: 24)
            }
        } else if gradient {
            Circle().fill(RadialGradient(stops: [
                .init(color: kind.color.opacity(0.7), location: 0),
                .init(color: kind.color.opacity(0.7), location: 12 / 19),
                .init(color: kind.color.opacity(0), location: 1)
            ], center: .center, startRadius: 0, endRadius: 19)).frame(width: 38, height: 38)
        } else {
            Circle().fill(kind.color.opacity(0.7)).frame(width: 24, height: 24)
        }
    }

    private func threshold(scale: Double, background: Double?) throws -> Double {
        var noise = 0.0
        for kind in kinds {
            for gradient in [false, true] {
                let (_, pixels) = try HUDLightDiagnosticFixture.render(control(kind, gap: false, gradient: gradient), scale: scale)
                noise = max(noise, pixels.rebound(radius: 12, outer: 19, background: background))
            }
        }
        // Margin is three RGBA8 quantization steps, fixed before production
        // inspection. It is never adjusted using the production result.
        return noise + 3.0 / 255
    }

    func testDetectorRecognizesArtificialGapAndAcceptsNaturalFade() throws {
        var csv = "scale,background,threshold,gapRebound\n"
        for scale in [1.0, 2] {
            for background in backgrounds {
                let tolerance = try threshold(scale: scale, background: background)
                for kind in kinds {
                    let (_, broken) = try HUDLightDiagnosticFixture.render(control(kind, gap: true, gradient: false), scale: scale)
                    let rebound = broken.rebound(radius: 12, outer: 19, background: background)
                    XCTAssertGreaterThan(rebound, tolerance, "诊断器必须识别人为透明分隔带")
                    csv += "\(scale),\(background.map(String.init(describing:)) ?? "transparent"),\(tolerance),\(rebound)\n"
                    for gradient in [false, true] {
                        let (_, good) = try HUDLightDiagnosticFixture.render(control(kind, gap: false, gradient: gradient), scale: scale)
                        XCTAssertLessThanOrEqual(good.rebound(radius: 12, outer: 19, background: background), tolerance)
                    }
                }
            }
        }
        try FileManager.default.createDirectory(at: HUDLightDiagnosticFixture.directory, withIntermediateDirectories: true)
        try csv.write(to: HUDLightDiagnosticFixture.directory.appendingPathComponent("calibration.csv"), atomically: true, encoding: .utf8)
    }

    func testExportProductionFixedFrameMatrixWithoutAssumingCause() throws {
        var summary = "kind,mode,q,scale,background,rebound,threshold,separationDetected\n"
        var rays = "kind,mode,q,scale,background,direction,radius,contrast,red,green,blue,alpha\n"
        var detected = 0, total = 0
        for scale in [1.0, 2] {
            let thresholds = try backgrounds.map { try threshold(scale: scale, background: $0) }
            for kind in kinds {
                for mode in modes {
                    for q in HUDLightDiagnosticFixture.progresses {
                        let visual = HUDLightDiagnosticFixture.visual(q)
                        let (image, pixels) = try HUDLightDiagnosticFixture.render(
                            StatusLightFrame(kind: kind, active: true, glow: mode, visual: visual), scale: scale)
                        let radius = 13 * visual.scale
                        let outer = radius + (mode == .strong ? 7 : 4) * q
                        let name = "\(kind)-\(mode)-q\(q)-s\(scale)"
                        try HUDLightDiagnosticFixture.save(image, name: name + "-transparent")
                        for (index, background) in backgrounds.enumerated() {
                            let label = background.map(String.init(describing:)) ?? "transparent"
                            let rebound = pixels.rebound(radius: radius, outer: outer, background: background)
                            let defect = rebound > thresholds[index]
                            total += 1
                            if defect { detected += 1 }
                            summary += "\(kind),\(mode),\(q),\(scale),\(label),\(rebound),\(thresholds[index]),\(defect)\n"
                            let profiles = pixels.rays(radius: radius, outer: outer, background: background)
                            for (direction, ray) in profiles.enumerated() {
                                for pixel in ray {
                                    rays += "\(kind),\(mode),\(q),\(scale),\(label),\(direction),\(pixel.r),\(pixel.contrast),\(pixel.rgba.map(String.init(describing:)).joined(separator: ","))\n"
                                }
                            }
                            if let background {
                                try HUDLightDiagnosticFixture.save(HUDLightDiagnosticFixture.composite(pixels, background: background),
                                                                  name: name + "-bg\(label)")
                            }
                            if kind == .running, mode == .standard, q == 0.25, scale == 2, background == 0.85 {
                                let points = profiles[0].map { "\(20 + ($0.r - radius + 2) * 60),\(180 - $0.contrast * 160)" }.joined(separator: " ")
                                let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"440\" height=\"200\"><rect width=\"440\" height=\"200\" fill=\"white\"/><polyline points=\"\(points)\" fill=\"none\" stroke=\"green\"/><text x=\"15\" y=\"15\">Contrast to gray background, actual pixels, q=0.25</text></svg>"
                                try svg.write(to: HUDLightDiagnosticFixture.directory.appendingPathComponent("radial-profile.svg"), atomically: true, encoding: .utf8)
                            }
                        }
                    }
                }
            }
        }
        try summary.write(to: HUDLightDiagnosticFixture.directory.appendingPathComponent("matrix.csv"), atomically: true, encoding: .utf8)
        try rays.write(to: HUDLightDiagnosticFixture.directory.appendingPathComponent("rays.csv"), atomically: true, encoding: .utf8)
        print("光晕静态诊断：\(total) 组合，分隔带检测 \(detected)，产物 \(HUDLightDiagnosticFixture.directory.path)")
        // Diagnostic-stage test checks successful sampling, not a predetermined
        // production root cause. Findings are exported even when nonzero.
        XCTAssertEqual(total, 384)
    }

    func testPersistentOffscreenSequenceAgainstFreshFrames() async throws {
        try FileManager.default.createDirectory(at: HUDLightDiagnosticFixture.directory, withIntermediateDirectories: true)
        var csv = "kind,mode,scale,cycle,index,q,completed,meanDifference,outerDifference\n"
        var maximum = 0.0
        for kind in kinds {
            for mode in modes {
                for scale in [1.0, 2] {
                    let state = HUDLightDiagnosticState()
                    let view = HUDLightDiagnosticView(state: state, kind: kind, mode: mode)
                    let hosting = NSHostingView(rootView: view)
                    hosting.frame = NSRect(x: 0, y: 0, width: 64, height: 64)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = scale
                    for cycle in 0..<2 {
                        for (index, q) in HUDLightDiagnosticFixture.sequence.enumerated() {
                            state.visual = HUDLightDiagnosticFixture.visual(q)
                            try await Task.sleep(nanoseconds: 20_000_000)
                            let live = try HUDLightDiagnosticPixels(image: XCTUnwrap(renderer.cgImage), scale: scale)
                            let (_, fresh) = try HUDLightDiagnosticFixture.render(
                                StatusLightFrame(kind: kind, active: true, glow: mode, visual: state.visual), scale: scale)
                            let difference = live.meanDifference(from: fresh)
                            let outerDifference = live.meanDifference(from: fresh, outside: 11)
                            maximum = max(maximum, difference)
                            csv += "\(kind),\(mode),\(scale),\(cycle),\(index),\(q),\(ProcessInfo.processInfo.systemUptime),\(difference),\(outerDifference)\n"
                            XCTAssertLessThanOrEqual(difference, 1.0 / 255)
                            XCTAssertLessThanOrEqual(outerDifference, 1.0 / 255)
                            XCTAssertTrue(hosting.rootView.state === state)
                        }
                    }
                    withExtendedLifetime(hosting) {}
                }
            }
        }
        try csv.write(to: HUDLightDiagnosticFixture.directory.appendingPathComponent("offscreen-sequence.csv"), atomically: true, encoding: .utf8)
        print("连续离屏诊断：同一渲染器最大平均差异 \(maximum)；未采样NSHostingView或WindowServer像素")
    }

    func testScreenPersistentShrinkingSequence() async throws {
        _ = NSApplication.shared
        let screen = try HUDScreenFixture(color: .white)
        defer { screen.close() }
        for kind in kinds {
            for mode in modes {
                let state = HUDLightDiagnosticState()
                let host = NSHostingView(rootView: HUDLightDiagnosticView(state: state, kind: kind, mode: mode))
                let panel = NonActivatingPanel(contentRect: NSRect(origin: screen.origin, size: NSSize(width: 64, height: 64)),
                                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.animationBehavior = .none
                panel.level = .floating
                panel.contentView = host
                panel.orderFrontRegardless()
                defer { panel.orderOut(nil); panel.contentView = nil; panel.close() }
                let number = panel.windowNumber
                let frame = panel.frame
                for cycle in 0..<2 {
                    for (index, q) in HUDLightDiagnosticFixture.sequence.enumerated() {
                        state.visual = HUDLightDiagnosticFixture.visual(q)
                        try await Task.sleep(nanoseconds: 40_000_000)
                        let pixels = try screen.captureNow(panel)
                        XCTAssertEqual(panel.frame, frame)
                        XCTAssertEqual(panel.windowNumber, number)
                        let scale = Double(pixels.width) / 64
                        // Capture uses the same ordinary WindowServer path as
                        // other screen tests. No forced hosting draw occurs.
                        let elapsed = ProcessInfo.processInfo.systemUptime
                        print("屏幕灯效采样 kind=\(kind) mode=\(mode) cycle=\(cycle) index=\(index) q=\(q) time=\(elapsed) number=\(number) scale=\(scale)")
                        // Persist captured data with a known provider layout.
                        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels.bytes) as CFData))
                        let image = try XCTUnwrap(CGImage(width: pixels.width, height: pixels.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                                         bytesPerRow: pixels.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
                        try HUDLightDiagnosticFixture.save(image, name: "screen-\(kind)-\(mode)-\(cycle)-\(index)-q\(q)")
                    }
                }
            }
        }
    }
}
