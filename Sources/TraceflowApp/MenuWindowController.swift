import AppKit
import SwiftUI
import TraceflowCore

@MainActor
final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class MenuWindowController {
    let model: AppModel
    private weak var statusItem: NSStatusItem?
    private var panel: MenuPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    var requestClose: (() -> Void)?
    var didClose: (() -> Void)?
    var isColorPopoverVisible = false
    private var ownedColorGeneration: Int?
    var isVisible: Bool { panel?.isVisible == true }

    init(model: AppModel, statusItem: NSStatusItem) {
        self.model = model
        self.statusItem = statusItem
    }

    func toggle() {
        if isVisible { requestDismiss() } else { show() }
    }

    func show() {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }
        if panel == nil {
            let window = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: 410, height: 440),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isFloatingPanel = true
            window.level = .popUpMenu
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MenuWindowView(model: model, controller: self))
            panel = window
        }
        guard let panel else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let frame = screen?.visibleFrame ?? anchor
        let width = min(410, frame.width)
        let height = min(440, frame.height)
        panel.setContentSize(NSSize(width: width, height: height))
        let x = min(max(anchor.midX - panel.frame.width / 2, frame.minX), frame.maxX - panel.frame.width)
        let y = max(frame.minY, min(anchor.minY - panel.frame.height - 4, frame.maxY - panel.frame.height))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        model.setMenuWindowVisible(true)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func requestDismiss() {
        if let requestClose { requestClose() } else { closeImmediately() }
    }

    func openColorPanel(sessionID: String) {
        model.sessionColorPanel.open(sessionID: sessionID)
        ownedColorGeneration = model.sessionColorPanel.sessionID == sessionID ? model.sessionColorPanel.generation : nil
    }

    func restoreEditingFocus() {
        guard let panel, panel.isVisible else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func closeImmediately() {
        if let generation = ownedColorGeneration, model.sessionColorPanel.generation == generation {
            model.sessionColorPanel.close()
        }
        ownedColorGeneration = nil
        isColorPopoverVisible = false
        didClose?()
        panel?.orderOut(nil)
        model.setMenuWindowVisible(false)
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
    }

    private func installMonitors() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isVisible, event.window !== self.panel else { return event }
            if event.window === NSColorPanel.shared || event.window === self.statusItem?.button?.window { return event }
            if self.isColorPopoverVisible, event.window?.parent === self.panel { return event }
            self.requestDismiss()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.requestDismiss() }
        }
    }
}

