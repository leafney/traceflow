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
        dragStarted?()
        drag = HUDDragTracking(pointer: NSEvent.mouseLocation, origin: window.frame.origin)
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
    private let background: HUDBackgroundView
    private var transparency: Int { geometry.transparency }
    private var transparencyObserver: AnyCancellable?
    private var accessibilityObserver: NSObjectProtocol?
    private var transitionTimer: Timer?
    private var transitionTarget: NSRect?
    private var layout: HUDLayoutMode
    private var geometry: HUDGeometryState
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
        geometry = HUDGeometryState(transparency: model.hudBackgroundTransparency, pinned: model.isHUDPinned)
        let size = HUDBackgroundAppearance(model.hudBackgroundTransparency).size(layout)
        let panel = NonActivatingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let content = Self.makeGlassContent(model: model, size: size)
        hostingView = content.hostingView
        background = content.background
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = model.hudBackgroundTransparency < 100
        // Our explicit mouse-up path commits the drag; avoid a second AppKit drag.
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.contentView = content.container
        panel.ignoresMouseEvents = geometry.interaction.ignoresMouseEvents
        super.init(window: panel)
        background.update(transparency)
        content.container.canBeginDrag = { [weak self] in
            self?.geometry.interaction.canBeginDrag ?? false
        }
        content.container.dragStarted = { [weak self] in
            guard let self else { return }
            self.finishTransition()
            guard self.geometry.beginDrag() else { return }
            self.positionRetry?.cancel()
            self.positionRetryDeadline = nil
        }
        content.container.dragFinished = { [weak self] moved in
            guard let self, self.geometry.finishDrag(frame: self.window?.frame ?? .zero, moved: moved, layout: self.layout) else { return }
            if moved {
                self.savePosition()
                self.isTemporaryPosition = false
            } else { self.ensureVisible() }
            self.updateGeometry(animated: true)
        }
        panel.delegate = self
        restorePosition()
        NotificationCenter.default.addObserver(self, selector: #selector(resetPosition), name: .traceflowResetHUDPosition, object: nil)
        layoutObserver = model.$hudLayoutMode.dropFirst().sink { [weak self] newLayout in
            // Published emits before the stored value changes. Defer so the
            // replacement root view observes the new layout mode, not the old one.
            DispatchQueue.main.async { self?.switchLayout(to: newLayout) }
        }
        transparencyObserver = model.$hudBackgroundTransparency.dropFirst().sink { [weak self] value in
            guard let self else { return }
            self.geometry.setTransparency(value)
            self.background.update(value)
            self.window?.hasShadow = value < 100
            self.window?.invalidateShadow()
            if !self.geometry.interaction.isDragging { self.updateGeometry(animated: true) }
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.background.update(self.transparency)
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { self.finishTransition() }
            }
        }
        pinObserver = model.$isHUDPinned.dropFirst().sink { [weak self] pinned in
            self?.setPinned(pinned)
        }
    }

    required init?(coder: NSCoder) { nil }
    func show() { restorePosition(); window?.orderFrontRegardless() }
    func hide() {
        window?.orderOut(nil)
        cancelInteraction()
        restorePosition()
    }

    private func cancelInteraction() {
        (window?.contentView as? HUDDragView)?.cancelDrag()
        geometry.cancelDrag()
        transitionTimer?.invalidate()
        transitionTimer = nil
        transitionTarget = nil
    }

    private func setPinned(_ pinned: Bool) {
        guard let window else { return }
        let shouldCancelDrag = geometry.setPinned(pinned)
        if shouldCancelDrag {
            (window.contentView as? HUDDragView)?.cancelDrag()
            restorePosition()
        }
        window.ignoresMouseEvents = geometry.interaction.ignoresMouseEvents
    }

    func windowDidMove(_ notification: Notification) {
        // AppKit also moves windows when screens disappear. Never persist here.
    }

    @objc private func resetPosition() {
        cancelInteraction()
        finishTransition()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        positionRetry?.cancel()
        positionRetryDeadline = nil
        isRestoringPosition = true
        geometry.restoreReference(HUDPositionGeometry.defaultFrame(for: layout, visible: screen.visibleFrame))
        if let frame = geometry.target(layout: layout, visible: screen.visibleFrame) { setDisplayFrame(frame) }
        isRestoringPosition = false
        savePosition()
        isTemporaryPosition = false
    }
    func ensureVisible() {
        cancelInteraction()
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
        guard newLayout != layout else { return }
        cancelInteraction()
        layout = newLayout
        restorePosition()
    }

    private func setDisplayFrame(_ frame: NSRect) {
        window?.setFrame(frame, display: true)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func finishTransition() {
        guard !geometry.interaction.isDragging else { return }
        transitionTimer?.invalidate()
        transitionTimer = nil
        if let target = transitionTarget { setDisplayFrame(target) }
        transitionTarget = nil
        model?.hudIconFraction = HUDBackgroundAppearance(transparency).compact ? 0 : 1
    }

    private func updateGeometry(animated: Bool) {
        guard let window, !geometry.interaction.isDragging else { return }
        let appearance = HUDBackgroundAppearance(transparency)
        guard let target = geometry.target(layout: layout, visible: bestScreen(for: window.frame)?.visibleFrame) else { return }
        if transitionTimer != nil, transitionTarget == target { return }
        transitionTimer?.invalidate()
        transitionTimer = nil
        let start = window.frame
        let fraction = model?.hudIconFraction ?? 1
        let endFraction = appearance.compact ? 0.0 : 1.0
        transitionTarget = target
        guard animated, window.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              start != target || fraction != endFraction else {
            finishTransition()
            return
        }
        let transition = HUDSizeTransition(start: start, target: target, initialIconFraction: fraction, targetIconFraction: endFraction)
        let began = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let sample = transition.sample(elapsed: ProcessInfo.processInfo.systemUptime - began)
                self.model?.hudIconFraction = sample.iconFraction
                self.setDisplayFrame(sample.frame)
                if sample.complete { self.finishTransition() }
            }
        }
        transitionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func restorePosition() {
        guard window != nil, !geometry.interaction.isDragging else { return }
        finishTransition()
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
        if let frame = decision.frame {
            geometry.restoreReference(frame)
            let screen = (!decision.isTemporary ? positions.load(layout).flatMap { self.screen(matching: $0) } : nil) ?? NSScreen.main
            if let display = geometry.target(layout: layout, visible: screen?.visibleFrame) { setDisplayFrame(display) }
        }
        if decision.shouldSave { savePosition() }
    }

    private func migrateLegacyFrame() -> Bool {
        guard let saved = defaults.string(forKey: "hudFrame") else { return false }
        let frame = NSRectFromString(saved)
        guard frame.width > 0, frame.height > 0, let screen = bestScreen(for: frame) else { return false }
        let resized = NSRect(origin: frame.origin, size: HUDPositionGeometry.size(for: .horizontal))
        geometry.restoreReference(resized)
        if let frame = geometry.target(layout: layout, visible: screen.visibleFrame) { setDisplayFrame(frame) }
        defaults.removeObject(forKey: "hudFrame")
        return true
    }

    private func savePosition() {
        guard let frame = window?.frame, let screen = bestScreen(for: frame) else { return }
        let visible = screen.visibleFrame
        let pixels = pixelSize(of: screen)
        let reference = HUDBackgroundAppearance.referenceFrame(frame, layout: layout)
        let relative = HUDPositionGeometry.relativePosition(of: reference, in: visible)
        let position = HUDPositionRecord(
            version: 3,
            displayUUID: displayUUID(for: screen),
            legacyDisplayID: displayID(for: screen),
            displayName: screen.localizedName,
            pixelWidth: pixels.width,
            pixelHeight: pixels.height,
            relativeX: relative.x,
            relativeY: relative.y,
            anchorX: ((layout == .horizontal ? reference.maxX : reference.minX) - visible.minX) / visible.width,
            anchorY: (reference.minY - visible.minY) / visible.height
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

    private static func makeGlassContent(model: AppModel, size: NSSize) -> (container: HUDDragView, hostingView: NSHostingView<HUDView>, background: HUDBackgroundView) {
        let container = HUDDragView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = min(size.width, size.height) / 2
        let background = HUDBackgroundView(frame: container.bounds)
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)
        let hosting = NSHostingView(rootView: HUDView(model: model))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        return (container, hosting, background)
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
