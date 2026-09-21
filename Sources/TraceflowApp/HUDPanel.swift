import AppKit
import SwiftUI

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HUDPanelController: NSWindowController, NSWindowDelegate {
    private let defaults = UserDefaults.standard

    init(model: AppModel) {
        let panel = NonActivatingPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 44), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        super.init(window: panel)
        panel.delegate = self
        restorePosition()
    }

    required init?(coder: NSCoder) { nil }
    func show() { window?.orderFrontRegardless() }
    func hide() { window?.orderOut(nil) }
    func windowDidMove(_ notification: Notification) { savePosition() }

    func ensureVisible() {
        guard let window else { return }
        let screens = NSScreen.screens
        if !screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) { positionAtTop(of: NSScreen.main ?? screens.first) }
    }

    private func restorePosition() {
        guard let window else { return }
        if let saved = defaults.string(forKey: "hudFrame") {
            let frame = NSRectFromString(saved)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { window.setFrame(frame, display: false); return }
        }
        positionAtTop(of: NSScreen.main)
    }

    private func positionAtTop(of screen: NSScreen?) {
        guard let screen, let window else { return }
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: visible.midX - 210, y: visible.maxY - 56))
        savePosition()
    }

    private func savePosition() { if let frame = window?.frame { defaults.set(NSStringFromRect(frame), forKey: "hudFrame") } }
}
