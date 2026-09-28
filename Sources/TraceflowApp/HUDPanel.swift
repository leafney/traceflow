import AppKit
import Combine
import CoreGraphics
import SwiftUI
import TraceflowCore

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HUDDragView: NSView {
    var canBeginDrag: (() -> Bool)?
    var dragStarted: (() -> Void)?
    var dragFinished: ((Bool) -> Void)?
    private var drag: HUDDragTracking?

    func cancelDrag() {
        drag = nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        guard let window, canBeginDrag?() == true else { return }
        drag = HUDDragTracking(pointer: NSEvent.mouseLocation, origin: window.frame.origin)
        dragStarted?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let drag else { return }
        window.setFrameOrigin(drag.origin(at: NSEvent.mouseLocation))
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        self.drag = nil
        dragFinished?(window.map { $0.frame.origin != drag.initialOrigin } ?? false)
    }
}

@MainActor
final class HUDPanelController: NSWindowController, NSWindowDelegate {
    private let defaults: UserDefaults
    private let positions: HUDPositionStore
    private weak var model: AppModel?
    private let hostingView: NSHostingView<HUDView>
    private var layout: HUDLayoutMode
    private var interaction: HUDInteractionState
    private var layoutObserver: AnyCancellable?
    private var pinObserver: AnyCancellable?
    private var isRestoringPosition = false
    private var isTemporaryPosition = false
    private var positionRetry: DispatchWorkItem?
    private var positionRetryDeadline: Date?

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        positions = HUDPositionStore(defaults: defaults)
        layout = model.hudLayoutMode
        interaction = HUDInteractionState(isPinned: model.isHUDPinned)
        let size = HUDPositionGeometry.size(for: layout)
        let panel = NonActivatingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let content = Self.makeGlassContent(model: model, size: size)
        hostingView = content.hostingView
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Our explicit mouse-up path commits the drag; avoid a second AppKit drag.
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.contentView = content.container
        panel.ignoresMouseEvents = interaction.ignoresMouseEvents
        super.init(window: panel)
        content.container.canBeginDrag = { [weak self] in
            self?.interaction.canBeginDrag ?? false
        }
        content.container.dragStarted = { [weak self] in
            guard let self, self.interaction.beginDrag() else { return }
            self.positionRetry?.cancel()
            self.positionRetryDeadline = nil
        }
        content.container.dragFinished = { [weak self] moved in
            guard let self, self.interaction.finishDrag() else { return }
            if moved {
                self.savePosition()
                self.isTemporaryPosition = false
            } else { self.ensureVisible() }
        }
        panel.delegate = self
        restorePosition()
        NotificationCenter.default.addObserver(self, selector: #selector(resetPosition), name: .traceflowResetHUDPosition, object: nil)
        layoutObserver = model.$hudLayoutMode.dropFirst().sink { [weak self] newLayout in
            // Published emits before the stored value changes. Defer so the
            // replacement root view observes the new layout mode, not the old one.
            DispatchQueue.main.async { self?.switchLayout(to: newLayout) }
        }
        pinObserver = model.$isHUDPinned.dropFirst().sink { [weak self] pinned in
            self?.setPinned(pinned)
        }
    }

    required init?(coder: NSCoder) { nil }
    func show() { restorePosition(); window?.orderFrontRegardless() }
    func hide() { window?.orderOut(nil) }

    private func setPinned(_ pinned: Bool) {
        guard let window else { return }
        let shouldCancelDrag = interaction.setPinned(pinned)
        if shouldCancelDrag {
            (window.contentView as? HUDDragView)?.cancelDrag()
            restorePosition()
        }
        window.ignoresMouseEvents = interaction.ignoresMouseEvents
    }

    func windowDidMove(_ notification: Notification) {
        // AppKit also moves windows when screens disappear. Never persist here.
    }

    @objc private func resetPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        positionRetry?.cancel()
        positionRetryDeadline = nil
        isRestoringPosition = true
        window?.setFrame(HUDPositionGeometry.defaultFrame(for: layout, visible: screen.visibleFrame), display: true)
        isRestoringPosition = false
        savePosition()
        isTemporaryPosition = false
    }
    func ensureVisible() {
        positionRetry?.cancel()
        positionRetryDeadline = Date().addingTimeInterval(HUDPositionRetryPolicy.duration)
        restorePosition()
        schedulePositionRetry()
    }

    private func schedulePositionRetry() {
        guard HUDPositionRetryPolicy.shouldRetry(isTemporary: isTemporaryPosition, now: Date(), deadline: positionRetryDeadline) else {
            positionRetryDeadline = nil
            positionRetry = nil
            return
        }
        let retry = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restorePosition()
            self.schedulePositionRetry()
        }
        positionRetry = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + HUDPositionRetryPolicy.interval, execute: retry)
    }

    private func switchLayout(to newLayout: HUDLayoutMode) {
        guard newLayout != layout, let window, let model else { return }
        isRestoringPosition = true
        for step in HUDLayoutTransitionPlanner.steps(from: layout, to: newLayout) {
            switch step {
            case .save:
                break // Drag completion already saved the user's permanent position.
            case let .resize(targetLayout, size):
                layout = targetLayout
                window.setContentSize(size)
                window.contentView?.frame = NSRect(origin: .zero, size: size)
                window.contentView?.layer?.cornerRadius = min(size.width, size.height) / 2
                // Recreate the root after the published layout value has settled.
                // This prevents the first vertical frame from retaining horizontal
                // layout measurements until an unrelated session update arrives.
                hostingView.rootView = HUDView(model: model)
                hostingView.frame = NSRect(origin: .zero, size: size)
                hostingView.needsLayout = true
                hostingView.layoutSubtreeIfNeeded()
                hostingView.needsDisplay = true
                hostingView.displayIfNeeded()
            case .restore:
                isRestoringPosition = false
                restorePosition()
            }
        }
    }

    private func restorePosition() {
        guard let window, !interaction.isDragging else { return }
        isRestoringPosition = true
        defer { isRestoringPosition = false }
        let positionResult = positions.loadResult(layout)
        if case .corrupted = positionResult {
            model?.logDiagnostic("error=hud_position_corrupted layout=\(layout.rawValue)")
        }
        if layout == .horizontal, case .missing = positionResult, migrateLegacyFrame() {
            savePosition()
            isTemporaryPosition = false
            return
        }
        let screens = NSScreen.screens
        let identities = screens.map { screen in
            let pixels = pixelSize(of: screen)
            return HUDScreenIdentity(uuid: displayUUID(for: screen), displayID: displayID(for: screen), name: screen.localizedName, pixelWidth: pixels.width, pixelHeight: pixels.height)
        }
        let mainIndex = NSScreen.main.flatMap { main in screens.firstIndex { $0 === main } } ?? screens.indices.first
        let decision = HUDPositionDecision.resolve(layout: layout, stored: positionResult, screens: identities, visibleFrames: screens.map(\.visibleFrame), mainIndex: mainIndex)
        isTemporaryPosition = decision.isTemporary
        if let frame = decision.frame, frame != window.frame { window.setFrame(frame, display: true) }
        if decision.shouldSave { savePosition() }
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

    private static func makeGlassContent(model: AppModel, size: NSSize) -> (container: HUDDragView, hostingView: NSHostingView<HUDView>) {
        let container = HUDDragView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = min(size.width, size.height) / 2
        let effect = NSVisualEffectView(frame: container.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = min(size.width, size.height) / 2
        effect.layer?.masksToBounds = true
        container.addSubview(effect)
        let hosting = NSHostingView(rootView: HUDView(model: model))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        return (container, hosting)
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
