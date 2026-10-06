import AppKit
import Combine
import CoreGraphics
import SwiftUI
import QuartzCore
import TraceflowCore

@MainActor
private final class HUDSizeDisplayLinkTarget: NSObject {
    var tick: ((CADisplayLink) -> Void)?

    @objc func displayFrame(_ link: CADisplayLink) { tick?(link) }
}

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
    private var hostingView: NSHostingView<HUDView>
    private var background: HUDBackgroundView
    private var transparency: Int { geometry.transparency }
    private var transparencyObserver: AnyCancellable?
    private var iconVisibilityObserver: AnyCancellable?
    private var accessibilityObserver: NSObjectProtocol?
    private var transitionDisplayLink: CADisplayLink?
    private let displayLinkTarget = HUDSizeDisplayLinkTarget()
    private var sizeTransition: HUDSizeTransition?
    private var transitionBegan: Double = 0
    private var transitionElapsed: Double = 0
    private var transitionTarget: NSRect?
    private var appliedDisplayMode: HUDWindowDisplayMode
    private var displayModeObserver: AnyCancellable?
    private var layout: HUDLayoutMode
    private var geometry: HUDGeometryState
    private var layoutObserver: AnyCancellable?
    private var pinObserver: AnyCancellable?
    private var isRestoringPosition = false
    private var isTemporaryPosition = false
    private var positionRetry: DispatchWorkItem?
    private(set) var positionRetryDeadline: Date?
    var isRetryingPosition: Bool { positionRetry != nil && positionRetryDeadline != nil }

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        positions = HUDPositionStore(defaults: defaults)
        layout = model.hudLayoutMode
        appliedDisplayMode = HUDWindowDisplayMode(session: model.displayedSession)
        geometry = HUDGeometryState(transparency: model.hudBackgroundTransparency, pinned: model.isHUDPinned,
                                    iconVisibilityMode: model.hudIconVisibilityMode)
        let size = geometry.appearance.size(layout)
        let content = Self.makePanelAssembly(model: model, layout: layout, mode: appliedDisplayMode, size: size,
                                             transparency: model.hudBackgroundTransparency,
                                             ignoresMouseEvents: geometry.interaction.ignoresMouseEvents)
        hostingView = content.hostingView
        background = content.background
        let panel = content.panel
        super.init(window: panel)
        configureInteraction(for: content.container)
        panel.delegate = self
        restorePosition()
        NotificationCenter.default.addObserver(self, selector: #selector(resetPosition), name: .traceflowResetHUDPosition, object: nil)
        layoutObserver = model.$hudLayoutMode.dropFirst().sink { [weak self] _ in
            // Published emits before the stored value changes. Read the final
            // layout/mode combination after both model properties have committed.
            DispatchQueue.main.async { self?.synchronizePresentation() }
        }
        displayModeObserver = model.$displayedSession
            .map { HUDWindowDisplayMode(session: $0) }.removeDuplicates().dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.synchronizePresentation() }
            }
        transparencyObserver = model.$hudBackgroundTransparency.dropFirst().sink { [weak self] value in
            guard let self else { return }
            self.geometry.setTransparency(value)
            self.background.update(value)
            if !self.geometry.interaction.isDragging { self.updateGeometry(animated: true) }
        }
        iconVisibilityObserver = model.$hudIconVisibilityMode.removeDuplicates().dropFirst().sink { [weak self] value in
            guard let self else { return }
            // Published emits before storage changes; carry the incoming value
            // into geometry instead of reading the model's previous mode.
            self.geometry.setIconVisibilityMode(value)
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

    private func configureInteraction(for container: HUDDragView) {
        container.canBeginDrag = { [weak self] in
            self?.geometry.interaction.canBeginDrag ?? false
        }
        container.dragStarted = { [weak self] in
            guard let self else { return }
            self.finishTransition()
            guard self.geometry.beginDrag() else { return }
            self.positionRetry?.cancel()
            self.positionRetryDeadline = nil
        }
        container.dragFinished = { [weak self] moved in
            guard let self, self.geometry.finishDrag(frame: self.window?.frame ?? .zero, moved: moved, layout: self.layout) else { return }
            if moved {
                self.savePosition()
                self.isTemporaryPosition = false
            } else { self.ensureVisible() }
            self.updateGeometry(animated: true)
        }
    }

    required init?(coder: NSCoder) { nil }
    deinit { transitionDisplayLink?.invalidate() }
    func show() {
        let placement = synchronizePresentation()
        if placement != .preserveCurrentGeometry { restorePosition() }
        window?.orderFrontRegardless()
    }
    func hide() {
        window?.orderOut(nil)
        cancelInteraction()
        restorePosition()
    }

    private func cancelInteraction() {
        (window?.contentView as? HUDDragView)?.cancelDrag()
        geometry.cancelDrag()
        stopSizeAnimation()
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

    func switchLayout(to newLayout: HUDLayoutMode) {
        guard newLayout == model?.hudLayoutMode else { return }
        synchronizePresentation()
    }

    @discardableResult
    private func synchronizePresentation() -> HUDPanelPlacement? {
        guard let model, window != nil else { return nil }
        let targetLayout = model.hudLayoutMode
        let targetMode = HUDWindowDisplayMode(session: model.displayedSession)
        guard targetLayout != layout || targetMode != appliedDisplayMode else { return nil }
        let placement: HUDPanelPlacement = targetLayout != layout
            ? .restoreLayoutPosition : .preserveCurrentGeometry
        replacePanel(layout: targetLayout, mode: targetMode, placement: placement)
        return placement
    }

    private func disconnectInteraction(for container: HUDDragView) {
        container.cancelDrag()
        container.canBeginDrag = nil
        container.dragStarted = nil
        container.dragFinished = nil
    }

    private func replacePanel(layout targetLayout: HUDLayoutMode, mode: HUDWindowDisplayMode,
                              placement: HUDPanelPlacement) {
        guard let model, let previous = window else { return }
        let wasVisible = previous.isVisible
        let previousFrame = previous.frame
        let wasDragging = geometry.interaction.isDragging
        let sizeTarget = transitionTarget
        var nextGeometry = geometry
        nextGeometry.cancelDrag()
        var frame = NSRect(origin: previousFrame.origin,
                           size: nextGeometry.appearance.size(targetLayout))
        if placement == .preserveCurrentGeometry {
            if wasDragging {
                nextGeometry.restoreReference(HUDBackgroundAppearance.referenceFrame(previousFrame, layout: layout))
                frame = nextGeometry.target(layout: layout, visible: bestScreen(for: previousFrame)?.visibleFrame) ?? frame
            } else if let sizeTarget {
                frame = sizeTarget
            } else if !NSScreen.screens.isEmpty {
                // Keep the unclamped reference as well as the visible frame.
                frame = previousFrame
            }
        } else {
            positionRetry?.cancel()
            positionRetry = nil
            positionRetryDeadline = nil
        }
        cancelInteraction()
        model.hudIconFraction = nextGeometry.appearance.compact ? 0 : 1
        let replacement = Self.makePanelAssembly(model: model, layout: targetLayout, mode: mode,
                                                 size: frame.size, transparency: transparency,
                                                 ignoresMouseEvents: nextGeometry.interaction.ignoresMouseEvents)
        replacement.panel.setFrame(frame, display: false)
        configureInteraction(for: replacement.container)
        replacement.panel.delegate = self

        // Both panels disable order-in/out animations. Retire the old surface
        // before showing the new one, in this same synchronous main-thread call.
        previous.orderOut(nil)
        previous.delegate = nil
        if let container = previous.contentView as? HUDDragView { disconnectInteraction(for: container) }
        window = replacement.panel
        hostingView = replacement.hostingView
        background = replacement.background
        layout = targetLayout
        appliedDisplayMode = mode
        geometry = nextGeometry
        if placement == .restoreLayoutPosition {
            geometry.restoreReference(HUDBackgroundAppearance.referenceFrame(frame, layout: layout))
            restorePosition()
        } else {
            setDisplayFrame(frame)
        }
        previous.contentView = nil
        previous.close()
        if wasVisible { replacement.panel.orderFrontRegardless() }
        if placement == .restoreLayoutPosition, isTemporaryPosition {
            positionRetryDeadline = Date().addingTimeInterval(HUDPositionRetryPolicy.duration)
            schedulePositionRetry()
        }
    }

    private func setDisplayFrame(_ frame: NSRect, immediate: Bool = true) {
        window?.setFrame(frame, display: immediate)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func stopSizeAnimation() {
        transitionDisplayLink?.invalidate()
        transitionDisplayLink = nil
        displayLinkTarget.tick = nil
        sizeTransition = nil
        transitionElapsed = 0
    }

    private func finishTransition() {
        guard !geometry.interaction.isDragging else { return }
        stopSizeAnimation()
        if let target = transitionTarget { setDisplayFrame(target) }
        transitionTarget = nil
        model?.hudIconFraction = geometry.appearance.compact ? 0 : 1
    }

    private func updateGeometry(animated: Bool) {
        guard let window, !geometry.interaction.isDragging else { return }
        let appearance = geometry.appearance
        guard let target = geometry.target(layout: layout, visible: bestScreen(for: window.frame)?.visibleFrame) else { return }
        if transitionDisplayLink != nil, transitionTarget == target { return }
        let velocity = sizeTransition?.iconVelocity(elapsed: transitionElapsed) ?? 0
        let start = window.frame
        let fraction = model?.hudIconFraction ?? 1
        let endFraction = appearance.compact ? 0.0 : 1.0
        transitionTarget = target
        guard animated, window.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              start != target || fraction != endFraction else {
            finishTransition()
            return
        }
        sizeTransition = HUDSizeTransition(start: start, target: target, initialIconFraction: fraction,
                                           targetIconFraction: endFraction, initialIconVelocity: velocity)
        transitionBegan = CACurrentMediaTime()
        transitionElapsed = 0
        // Keep the same display clock on reversal; the proxy does not retain us.
        if transitionDisplayLink == nil {
            displayLinkTarget.tick = { [weak self] link in self?.renderSizeTransition(link) }
            let link = hostingView.displayLink(target: displayLinkTarget, selector: #selector(HUDSizeDisplayLinkTarget.displayFrame(_:)))
            transitionDisplayLink = link
            link.add(to: .main, forMode: .common)
        }
    }

    private func renderSizeTransition(_ link: CADisplayLink) {
        guard let sizeTransition else { return }
        transitionElapsed = max(0, link.targetTimestamp - transitionBegan)
        let sample = sizeTransition.sample(elapsed: transitionElapsed)
        // Commit size and content together for the next screen frame; avoid a
        // synchronous repaint of the glass and hosting tree on every tick.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        model?.hudIconFraction = sample.iconFraction
        setDisplayFrame(sample.frame, immediate: false)
        hostingView.layoutSubtreeIfNeeded()
        CATransaction.commit()
        if sample.complete { finishTransition() }
    }

    private func restorePosition() {
        guard window != nil, !geometry.interaction.isDragging else { return }
        finishTransition()
        isRestoringPosition = true
        defer { isRestoringPosition = false }
        let screens = NSScreen.screens
        let identities = screens.map { screen in
            let pixels = pixelSize(of: screen)
            return HUDScreenIdentity(uuid: displayUUID(for: screen), displayID: displayID(for: screen), name: screen.localizedName, pixelWidth: pixels.width, pixelHeight: pixels.height)
        }
        let positionResult = positions.seedIfMissing(layout, screens: identities, visibleFrames: screens.map(\.visibleFrame))
        if case .corrupted = positionResult {
            model?.logDiagnostic("error=hud_position_corrupted layout=\(layout.rawValue)")
        }
        if case let .corruptedSource(source) = positionResult {
            model?.logDiagnostic("error=hud_position_corrupted layout=\(source.rawValue) target_layout=\(layout.rawValue)")
        }
        if layout == .horizontalRight, case .missing = positionResult, migrateLegacyFrame() {
            savePosition()
            isTemporaryPosition = false
            return
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
        let resized = NSRect(origin: frame.origin, size: HUDPositionGeometry.size(for: .horizontalRight))
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
            anchorX: ((layout == .horizontalRight ? reference.maxX : reference.minX) - visible.minX) / visible.width,
            anchorY: ((layout == .verticalTop ? reference.maxY : reference.minY) - visible.minY) / visible.height
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

    private struct HUDPanelAssembly {
        let panel: NonActivatingPanel
        let container: HUDDragView
        let hostingView: NSHostingView<HUDView>
        let background: HUDBackgroundView
    }

    private static func makePanelAssembly(model: AppModel, layout: HUDLayoutMode, mode: HUDWindowDisplayMode, size: NSSize,
                                          transparency: Int, ignoresMouseEvents: Bool) -> HUDPanelAssembly {
        let panel = NonActivatingPanel(contentRect: NSRect(origin: .zero, size: size),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let content = makeGlassContent(model: model, layout: layout, mode: mode, size: size)
        content.background.update(transparency)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Avoid system shadows derived from translucent HUD content.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        // orderOut's logical visibility alone cannot rule out an animated
        // outgoing surface. Layout replacement must not cross-fade windows.
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = ignoresMouseEvents
        panel.contentView = content.container
        return HUDPanelAssembly(panel: panel, container: content.container,
                                hostingView: content.hostingView, background: content.background)
    }

    private static func makeGlassContent(model: AppModel, layout: HUDLayoutMode, mode: HUDWindowDisplayMode, size: NSSize) -> (container: HUDDragView, hostingView: NSHostingView<HUDView>, background: HUDBackgroundView) {
        let container = HUDDragView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = min(size.width, size.height) / 2
        let background = HUDBackgroundView(frame: container.bounds)
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)
        let hosting = makeHostingView(model: model, layout: layout, mode: mode, frame: container.bounds)
        container.addSubview(hosting)
        return (container, hosting, background)
    }

    private static func makeHostingView(model: AppModel, layout: HUDLayoutMode, mode: HUDWindowDisplayMode, frame: NSRect) -> NSHostingView<HUDView> {
        let hosting = NSHostingView(rootView: HUDView(model: model, layout: layout,
                                                      presentation: HUDWindowPresentation(model: model, mode: mode)))
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]
        return hosting
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
