import AppKit
import TraceflowCore

final class HUDSolidBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

final class HUDBackgroundView: NSView {
    private let solid = HUDSolidBackground()
    private let material = NSVisualEffectView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 20
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        for view in [solid, material] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { nil }

    func update(_ transparency: Int) {
        let appearance = HUDBackgroundAppearance(transparency)
        alphaValue = appearance.backgroundAlpha
        solid.alphaValue = appearance.backgroundAlpha
        material.alphaValue = appearance.materialAlpha
        solid.needsDisplay = true
    }
}
