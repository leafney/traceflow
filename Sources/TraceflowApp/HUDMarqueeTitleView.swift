import AppKit
import Combine
import SwiftUI
import TraceflowCore

struct HUDMarqueeTitleView: NSViewRepresentable {
    let title: String
    let vertical: Bool
    let color: HUDTitleColor
    var offset: CGFloat = 0
    var reduceMotion = false
    var sessionID: String? = nil
    var generation: UInt64? = nil
    var contentRevision: UInt64? = nil
    var coordinator: HUDMarqueeCoordinator? = nil

    func makeNSView(context: Context) -> HUDMarqueeNSView {
        HUDMarqueeNSView(title: title, vertical: vertical, color: color)
    }
    func updateNSView(_ view: HUDMarqueeNSView, context: Context) {
        view.configure(title: title, vertical: vertical, color: color)
        if generation == nil {
            view.offset = offset
            view.reduceMotion = reduceMotion
        }
        view.bind(coordinator: coordinator, generation: generation, sessionID: sessionID, title: title, contentRevision: contentRevision)
    }
}

final class HUDMarqueeNSView: NSView {
    private(set) var textLayout: HUDTitleTextLayout
    private var subscription: AnyCancellable?
    private weak var coordinator: HUDMarqueeCoordinator?
    private var generation: UInt64?
    private var contentRevision: UInt64?
    private var sessionID: String?
    private var boundTitle: String?
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
    func bind(coordinator: HUDMarqueeCoordinator?, generation: UInt64?, sessionID: String?, title: String, contentRevision: UInt64? = nil) {
        let revision = contentRevision ?? coordinator?.contentRevision
        if self.coordinator !== coordinator || self.generation != generation || self.sessionID != sessionID || boundTitle != title || self.contentRevision != revision {
            subscription = nil
            self.coordinator = coordinator
            self.generation = generation
            self.contentRevision = revision
            self.sessionID = sessionID
            boundTitle = title
            if let coordinator, generation != nil {
                subscription = coordinator.frames.sink { [weak self] frame in self?.apply(frame) }
            }
        }
        updateFormalBackingScale()
        if let frame = coordinator?.currentFrame { apply(frame) }
    }

    private func apply(_ frame: HUDMarqueeCoordinator.Frame) {
        guard frame.generation == generation, frame.contentRevision == contentRevision, frame.sessionID == sessionID, frame.layout.title == boundTitle else { return }
        textLayout = frame.layout
        offset = frame.offset
        reduceMotion = frame.reduceMotion
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateFormalBackingScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard window != nil else { return }
        if generation == nil { configure(title: textLayout.title, vertical: textLayout.vertical, color: color) }
        updateFormalBackingScale()
    }

    private func updateFormalBackingScale() {
        // A detached/outgoing view must never configure the current presentation.
        guard let window, let generation, let contentRevision, let boundTitle else { return }
        coordinator?.updateBackingScale(window.backingScaleFactor, generation: generation,
                                        contentRevision: contentRevision, sessionID: sessionID, title: boundTitle)
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
