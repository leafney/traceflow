import AppKit
import Combine
import CoreGraphics
import SwiftUI
import TraceflowCore

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HUDPanelController: NSWindowController, NSWindowDelegate {
    private let defaults: UserDefaults
    private let positions: HUDPositionStore
    private weak var model: AppModel?
    private var layout: HUDLayoutMode
    private var layoutObserver: AnyCancellable?
    private var isRestoringPosition = false

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        positions = HUDPositionStore(defaults: defaults)
        layout = model.hudLayoutMode
        let size = HUDPositionGeometry.size(for: layout)
        let panel = NonActivatingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = Self.makeGlassContent(model: model, size: size)
        super.init(window: panel)
        panel.delegate = self
        restorePosition()
        NotificationCenter.default.addObserver(self, selector: #selector(resetPosition), name: .traceflowResetHUDPosition, object: nil)
        layoutObserver = model.$hudLayoutMode.dropFirst().sink { [weak self] newLayout in
            self?.switchLayout(to: newLayout)
        }
    }

    required init?(coder: NSCoder) { nil }
    func show() { window?.orderFrontRegardless() }
    func hide() { window?.orderOut(nil) }

    func windowDidMove(_ notification: Notification) {
        guard !isRestoringPosition else { return }
        savePosition()
    }

    @objc private func resetPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        isRestoringPosition = true
        window?.setFrame(HUDPositionGeometry.defaultFrame(for: layout, visible: screen.visibleFrame), display: true)
        isRestoringPosition = false
        savePosition()
    }
    func ensureVisible() { restorePosition() }

    private func switchLayout(to newLayout: HUDLayoutMode) {
        guard newLayout != layout, let window else { return }
        isRestoringPosition = true
        for step in HUDLayoutTransitionPlanner.steps(from: layout, to: newLayout) {
            switch step {
            case .save:
                savePosition()
            case let .resize(targetLayout, size):
                layout = targetLayout
                window.setContentSize(size)
                window.contentView?.frame = NSRect(origin: .zero, size: size)
                window.contentView?.layer?.cornerRadius = min(size.width, size.height) / 2
            case .restore:
                isRestoringPosition = false
                restorePosition()
            }
        }
    }

    private func restorePosition() {
        guard let window else { return }
        isRestoringPosition = true
        defer {
            isRestoringPosition = false
            savePosition()
        }
        let positionResult = positions.loadResult(layout)
        if case .corrupted = positionResult {
            model?.logDiagnostic("error=hud_position_corrupted layout=\(layout.rawValue)")
        }
        if case let .loaded(position) = positionResult,
           let screen = screen(matching: position) {
            let frame = HUDPositionGeometry.restoredFrame(for: layout, relativeX: position.relativeX, relativeY: position.relativeY, visible: screen.visibleFrame)
            window.setFrame(frame, display: true)
            return
        }
        if layout == .horizontal, case .missing = positionResult, migrateLegacyFrame() { return }
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            window.setFrame(HUDPositionGeometry.defaultFrame(for: layout, visible: screen.visibleFrame), display: true)
        }
    }

    private func migrateLegacyFrame() -> Bool {
        guard let saved = defaults.string(forKey: "hudFrame") else { return false }
        let frame = NSRectFromString(saved)
        guard frame.width > 0, frame.height > 0, let screen = bestScreen(for: frame) else { return false }
        let resized = NSRect(origin: frame.origin, size: HUDPositionGeometry.size(for: .horizontal))
        window?.setFrame(HUDPositionGeometry.clamped(resized, to: screen.visibleFrame), display: true)
        defaults.removeObject(forKey: "hudFrame")
        return true
    }

    private func savePosition() {
        guard let frame = window?.frame, let screen = bestScreen(for: frame) else { return }
        let visible = screen.visibleFrame
        let pixels = pixelSize(of: screen)
        let relative = HUDPositionGeometry.relativePosition(of: frame, in: visible)
        let position = HUDPositionRecord(
            version: 3,
            displayUUID: displayUUID(for: screen),
            legacyDisplayID: displayID(for: screen),
            displayName: screen.localizedName,
            pixelWidth: pixels.width,
            pixelHeight: pixels.height,
            relativeX: relative.x,
            relativeY: relative.y
        )
        positions.save(position, for: layout)
    }

    private func bestScreen(for frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let containing = NSScreen.screens.first(where: { $0.visibleFrame.contains(center) }) { return containing }
        return NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }
    }

    private func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func displayUUID(for screen: NSScreen) -> String? {
        guard let id = displayID(for: screen), let uuid = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    private func pixelSize(of screen: NSScreen) -> (width: Int, height: Int) {
        (
            Int((screen.frame.width * screen.backingScaleFactor).rounded()),
            Int((screen.frame.height * screen.backingScaleFactor).rounded())
        )
    }

    private func screen(matching position: HUDPositionRecord) -> NSScreen? {
        let screens = NSScreen.screens
        let identities = screens.map { screen in
            let pixels = pixelSize(of: screen)
            return HUDScreenIdentity(uuid: displayUUID(for: screen), displayID: displayID(for: screen),
                                     name: screen.localizedName, pixelWidth: pixels.width, pixelHeight: pixels.height)
        }
        guard let index = HUDPositionGeometry.matchingScreen(for: position, among: identities) else { return nil }
        return screens[index]
    }

    private static func makeGlassContent(model: AppModel, size: NSSize) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = min(size.width, size.height) / 2
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
