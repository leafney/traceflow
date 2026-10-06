import CoreGraphics

/// Keeps the intended reference separate from the screen-clamped display frame.
public struct HUDGeometryState {
    public private(set) var interaction: HUDInteractionState
    public private(set) var transparency: Int
    public private(set) var iconVisibilityMode: HUDIconVisibilityMode
    public private(set) var reference: CGRect?

    public init(transparency: Int, pinned: Bool, iconVisibilityMode: HUDIconVisibilityMode = .automatic) {
        self.transparency = HUDBackgroundAppearance.normalize(Double(transparency))
        self.iconVisibilityMode = iconVisibilityMode
        interaction = HUDInteractionState(isPinned: pinned)
    }

    public var appearance: HUDBackgroundAppearance {
        HUDBackgroundAppearance(transparency, iconVisibilityMode: iconVisibilityMode)
    }

    public mutating func setIconVisibilityMode(_ mode: HUDIconVisibilityMode) {
        iconVisibilityMode = mode
    }

    public mutating func setTransparency(_ value: Int) {
        transparency = HUDBackgroundAppearance.normalize(Double(value))
    }

    public mutating func restoreReference(_ frame: CGRect) { reference = frame }

    public func target(layout: HUDLayoutMode, visible: CGRect?) -> CGRect? {
        guard !interaction.isDragging, let reference else { return nil }
        let display = appearance.displayFrame(reference, layout: layout)
        return visible.map { HUDPositionGeometry.clamped(display, to: $0) } ?? display
    }

    @discardableResult
    public mutating func beginDrag() -> Bool { interaction.beginDrag() }

    @discardableResult
    public mutating func finishDrag(frame: CGRect, moved: Bool, layout: HUDLayoutMode) -> Bool {
        guard interaction.finishDrag() else { return false }
        if moved { reference = HUDBackgroundAppearance.referenceFrame(frame, layout: layout) }
        return true
    }

    public mutating func cancelDrag() { interaction.cancelDrag() }

    @discardableResult
    public mutating func setPinned(_ pinned: Bool) -> Bool { interaction.setPinned(pinned) }
}
