import AppKit
import SwiftUI
import TraceflowCore

struct HUDMarqueeTitleView: NSViewRepresentable {
    let title: String
    let vertical: Bool
    let color: HUDTitleColor
    var offset: CGFloat = 0
    var reduceMotion = false

    func makeNSView(context: Context) -> HUDMarqueeNSView {
        HUDMarqueeNSView(title: title, vertical: vertical, color: color)
    }
    func updateNSView(_ view: HUDMarqueeNSView, context: Context) {
        view.configure(title: title, vertical: vertical, color: color)
        view.offset = offset
        view.reduceMotion = reduceMotion
    }
}

final class HUDMarqueeNSView: NSView {
    private(set) var textLayout: HUDTitleTextLayout
    private var color: HUDTitleColor
    var offset: CGFloat = 0 { didSet { if offset != oldValue { needsDisplay = true } } }
    var reduceMotion = false { didSet { if reduceMotion != oldValue { needsDisplay = true } } }
    override var isFlipped: Bool { true }

    init(title: String, vertical: Bool, color: HUDTitleColor) {
        textLayout = HUDTitleTextLayout(title: title, vertical: vertical)
        self.color = color
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }

    func configure(title: String, vertical: Bool, color: HUDTitleColor) {
        let scale = window?.backingScaleFactor ?? 2
        if title != textLayout.title || vertical != textLayout.vertical || scale != textLayout.backingScale {
            textLayout = HUDTitleTextLayout(title: title, vertical: vertical, backingScale: scale)
            needsDisplay = true
        }
        if self.color != color { self.color = color; needsDisplay = true }
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        configure(title: textLayout.title, vertical: textLayout.vertical, color: color)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: textLayout.vertical ? 0 : HUDMetrics.titleInset,
                            y: textLayout.vertical ? HUDMetrics.titleInset : 0)
        textLayout.draw(in: context, offset: offset, color: color == .white ? .white : .black, reduceMotion: reduceMotion)
        context.restoreGState()
    }
}
