import AppKit
import SwiftUI
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class HUDLightRenderingTests: XCTestCase {
    func testEnhancedHaloChangesRenderedEdgeWithoutChangingLayout() throws {
        let peak = HUDLightAnimation.parameters(for: .running, isActive: true, referenceTime: 1.15, reduceMotion: false)
        let standard = try frame(mode: .standard, active: true, visual: peak)
        let enhanced = try frame(mode: .strong, active: true, visual: peak)
        XCTAssertGreaterThan(alpha(enhanced, radius: 16...19), alpha(standard, radius: 16...19) + 0.05)
        let inactive = HUDLightAnimation.parameters(for: .running, isActive: false, referenceTime: 1.15, reduceMotion: false)
        let off = try frame(mode: .strong, active: false, visual: inactive)
        XCTAssertLessThan(alpha(off, radius: 16...19), 0.01)
        XCTAssertEqual(alpha(off, radius: 0...8), 0.18, accuracy: 0.02)
        let reduced = HUDLightAnimation.parameters(for: .running, isActive: true, referenceTime: 0, reduceMotion: true)
        let still = try frame(mode: .strong, active: true, visual: reduced)
        XCTAssertGreaterThan(alpha(still, radius: 16...19), 0.01)
        XCTAssertEqual(alpha(still, radius: 0...8), 1, accuracy: 0.01)
        let renderer = ImageRenderer(content: StatusLightFrame(kind: .running, active: true, glow: .strong, visual: peak))
        XCTAssertEqual(try XCTUnwrap(renderer.cgImage).width, 26)
        XCTAssertEqual(try XCTUnwrap(renderer.cgImage).height, 26)
    }

    func testActualHUDUpdatesAfterHooksAndModeChangesInEveryLayout() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        for layout in HUDLayoutMode.allCases {
            fixture.model.hudLayoutMode = layout
            let renderer = ImageRenderer(content: HUDView(model: fixture.model))
            var previousStateImage: Data?
            for (event, state) in [(HookEventName.userPromptSubmit, SessionRuntimeState.running),
                                   (.stop, .completed), (.permissionRequest, .attention), (.interrupt, .idle)] {
                try await fixture.hook("lights", event: event)
                if state == .idle { XCTAssertNil(fixture.model.displayedSession) }
                else { XCTAssertEqual(fixture.model.displayedSession?.state, state) }
                fixture.model.hudGlowMode = .standard
                // SwiftUI processes Published invalidation on the next main-loop turn.
                try await Task.sleep(nanoseconds: 50_000_000)
                let standard = try XCTUnwrap(renderer.cgImage)
                fixture.model.hudGlowMode = .strong
                try await Task.sleep(nanoseconds: 50_000_000)
                let enhanced = try XCTUnwrap(renderer.cgImage)
                XCTAssertEqual(enhanced.width, layout.isHorizontal ? 420 : 40)
                XCTAssertEqual(enhanced.height, layout.isHorizontal ? 40 : 420)
                let a = try XCTUnwrap(standard.dataProvider?.data) as Data
                let b = try XCTUnwrap(enhanced.dataProvider?.data) as Data
                if let previousStateImage {
                    XCTAssertNotEqual(previousStateImage, a, "真实状态变化必须更新原生画面")
                }
                previousStateImage = a
                if state == .idle { XCTAssertEqual(a, b, "未点亮时切换光晕不应改变画面") }
                else if state == .completed { XCTAssertNotEqual(a, b, "点亮时切换光晕必须更新画面") }
            }
        }
    }

    private func frame(mode: HUDGlowMode, active: Bool, visual: HUDLightVisualParameters) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: StatusLightFrame(kind: .running, active: active, glow: mode, visual: visual)
            .frame(width: 64, height: 64))
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }

    private func alpha(_ image: NSBitmapImageRep, radius: ClosedRange<Double>) -> Double {
        var sum = 0.0
        var count = 0
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                let r = hypot(Double(x) + 0.5 - 32, Double(y) + 0.5 - 32)
                if radius.contains(r) {
                    sum += Double(image.colorAt(x: x, y: y)?.alphaComponent ?? 0)
                    count += 1
                }
            }
        }
        return sum / Double(max(1, count))
    }
}
