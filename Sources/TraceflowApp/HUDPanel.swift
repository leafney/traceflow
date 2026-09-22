import AppKit
import SwiftUI

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct HUDPosition: Codable {
    let version: Int
    let displayID: UInt32
    let relativeX: Double
    let relativeY: Double
}

@MainActor
final class HUDPanelController: NSWindowController, NSWindowDelegate {
    private static let size = NSSize(width: 420, height: 40)
    private let defaults = UserDefaults.standard
    private var isRestoringPosition = false

    init(model: AppModel) {
        let panel = NonActivatingPanel(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = Self.makeGlassContent(model: model)
        super.init(window: panel)
        panel.delegate = self
        restorePosition()
        NotificationCenter.default.addObserver(self, selector: #selector(resetPosition), name: .traceflowResetHUDPosition, object: nil)
    }

    required init?(coder: NSCoder) { nil }
    func show() { window?.orderFrontRegardless() }
    func hide() { window?.orderOut(nil) }

    func windowDidMove(_ notification: Notification) {
        guard !isRestoringPosition else { return }
        savePosition()
    }

    @objc private func resetPosition() { positionAtTop(of: NSScreen.main ?? NSScreen.screens.first, save: true) }
    func ensureVisible() { restorePosition() }

    private func restorePosition() {
        guard let window else { return }
        isRestoringPosition = true
        defer { isRestoringPosition = false }
        if let data = defaults.data(forKey: "hudPositionV2"),
           let position = try? JSONDecoder().decode(HUDPosition.self, from: data),
           let screen = NSScreen.screens.first(where: { displayID(for: $0) == position.displayID }) {
            let visible = screen.visibleFrame
            let rangeX = max(0, visible.width - Self.size.width)
            let rangeY = max(0, visible.height - Self.size.height)
            let origin = NSPoint(
                x: visible.minX + rangeX * min(1, max(0, position.relativeX)),
                y: visible.minY + rangeY * min(1, max(0, position.relativeY))
            )
            window.setFrame(NSRect(origin: origin, size: Self.size), display: false)
            return
        }
        if migrateLegacyFrame() { return }
        positionAtTop(of: NSScreen.main ?? NSScreen.screens.first, save: true)
    }

    private func migrateLegacyFrame() -> Bool {
        guard let saved = defaults.string(forKey: "hudFrame") else { return false }
        let frame = NSRectFromString(saved)
        guard frame.width > 0, frame.height > 0, let screen = bestScreen(for: frame) else { return false }
        window?.setFrame(NSRect(origin: clampedOrigin(frame.origin, on: screen), size: Self.size), display: false)
        defaults.removeObject(forKey: "hudFrame")
        savePosition()
        return true
    }

    private func positionAtTop(of screen: NSScreen?, save: Bool) {
        guard let screen, let window else { return }
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: visible.midX - Self.size.width / 2, y: visible.maxY - Self.size.height - 12))
        if save { savePosition() }
    }

    private func savePosition() {
        guard let frame = window?.frame, let screen = bestScreen(for: frame), let displayID = displayID(for: screen) else { return }
        let visible = screen.visibleFrame
        let rangeX = max(1, visible.width - frame.width)
        let rangeY = max(1, visible.height - frame.height)
        let position = HUDPosition(
            version: 2,
            displayID: displayID,
            relativeX: min(1, max(0, (frame.minX - visible.minX) / rangeX)),
            relativeY: min(1, max(0, (frame.minY - visible.minY) / rangeY))
        )
        if let data = try? JSONEncoder().encode(position) { defaults.set(data, forKey: "hudPositionV2") }
    }

    private func bestScreen(for frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let containing = NSScreen.screens.first(where: { $0.visibleFrame.contains(center) }) { return containing }
        return NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }
    }

    private func clampedOrigin(_ origin: NSPoint, on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        return NSPoint(
            x: min(visible.maxX - Self.size.width, max(visible.minX, origin.x)),
            y: min(visible.maxY - Self.size.height, max(visible.minY, origin.y))
        )
    }

    private func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func makeGlassContent(model: AppModel) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = size.height / 2
        container.layer?.masksToBounds = true
        let effect = NSVisualEffectView(frame: container.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        container.addSubview(effect)
        let hosting = NSHostingView(rootView: HUDView(model: model))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        return container
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
