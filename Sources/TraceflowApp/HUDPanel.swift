import AppKit
import CoreGraphics
import SwiftUI

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct HUDPosition: Codable {
    let version: Int
    let displayUUID: String?
    let legacyDisplayID: UInt32?
    let displayName: String?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let relativeX: Double
    let relativeY: Double

    enum CodingKeys: String, CodingKey {
        case version, displayUUID, displayName, pixelWidth, pixelHeight, relativeX, relativeY
        case legacyDisplayID = "displayID"
    }
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
           let screen = screen(matching: position) {
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
        guard let frame = window?.frame, let screen = bestScreen(for: frame) else { return }
        let visible = screen.visibleFrame
        let pixels = pixelSize(of: screen)
        let rangeX = max(1, visible.width - frame.width)
        let rangeY = max(1, visible.height - frame.height)
        let position = HUDPosition(
            version: 3,
            displayUUID: displayUUID(for: screen),
            legacyDisplayID: displayID(for: screen),
            displayName: screen.localizedName,
            pixelWidth: pixels.width,
            pixelHeight: pixels.height,
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

    private func screen(matching position: HUDPosition) -> NSScreen? {
        if let uuid = position.displayUUID,
           let exact = NSScreen.screens.first(where: { displayUUID(for: $0) == uuid }) { return exact }
        if let id = position.legacyDisplayID,
           let legacy = NSScreen.screens.first(where: { displayID(for: $0) == id }) { return legacy }
        if let name = position.displayName,
           let width = position.pixelWidth,
           let height = position.pixelHeight,
           let matched = NSScreen.screens.first(where: {
               let size = pixelSize(of: $0)
               return $0.localizedName == name && size.width == width && size.height == height
           }) { return matched }
        if let name = position.displayName {
            return NSScreen.screens.first(where: { $0.localizedName == name })
        }
        return nil
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
