import AppKit
import CoreText
import SwiftUI
import TraceflowCore

struct VerticalMixedTitleView: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> MixedTitleNSView {
        MixedTitleNSView(title: title)
    }

    func updateNSView(_ view: MixedTitleNSView, context: Context) {
        view.title = title
    }
}

final class MixedTitleNSView: NSView {
    var title: String {
        didSet {
            guard title != oldValue else { return }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let font = roundedFont()
        let segments = VerticalTitleParser.segments(for: title).isEmpty
            ? VerticalTitleParser.segments(for: "Traceflow")
            : VerticalTitleParser.segments(for: title)
        let scale = window?.backingScaleFactor ?? 2
        let contentLength = max(0, bounds.height - 12)
        let ellipsisAdvance = hanAdvance(font: font, scale: scale)
        let layout = VerticalTitleMeasurer.layout(
            segments: segments,
            maximumLength: contentLength,
            ellipsisAdvance: ellipsisAdvance,
            advance: { [weak self] segment in self?.advance(for: segment, font: font, scale: scale) ?? 0 }
        )

        var cursor = align(6, scale: scale)
        let center = align(bounds.midX, scale: scale)
        context.setFillColor(NSColor.labelColor.cgColor)
        for segment in layout.visibleSegments {
            let length = advance(for: segment, font: font, scale: scale)
            switch segment {
            case .gap:
                break
            case let .han(character):
                drawUpright(String(character), centerX: center, top: cursor, font: font, context: context, scale: scale)
            case let .latin(text):
                drawClockwise(text, centerX: center, top: cursor, font: font, context: context, scale: scale)
            }
            cursor = align(cursor + length, scale: scale)
        }
        if layout.showsEllipsis {
            drawUpright("…", centerX: center, top: bounds.height - 6 - ellipsisAdvance, font: font, context: context, scale: scale)
        }
    }

    private func roundedFont() -> NSFont {
        let base = NSFont.systemFont(ofSize: 13, weight: .medium)
        if let descriptor = base.fontDescriptor.withDesign(.rounded), let rounded = NSFont(descriptor: descriptor, size: 13) {
            return rounded
        }
        return base
    }

    private func advance(for segment: VerticalTitleSegment, font: NSFont, scale: CGFloat) -> Double {
        switch segment {
        case .gap: return 4
        case .han: return Double(hanAdvance(font: font, scale: scale))
        case let .latin(text): return Double(align(lineWidth(text, font: font), scale: scale))
        }
    }

    private func hanAdvance(font: NSFont, scale: CGFloat) -> CGFloat {
        ceil((font.ascender - font.descender + font.leading) * scale) / scale
    }

    private func lineWidth(_ text: String, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), nil, nil, nil))
    }

    private func drawUpright(_ text: String, centerX: CGFloat, top: CGFloat, font: NSFont, context: CGContext, scale: CGFloat) {
        let line = line(text, font: font)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: align(centerX - width / 2, scale: scale), y: align(-(top + font.ascender), scale: scale))
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawClockwise(_ text: String, centerX: CGFloat, top: CGFloat, font: NSFont, context: CGContext, scale: CGFloat) {
        let line = line(text, font: font)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.saveGState()
        context.translateBy(x: align(centerX + font.ascender / 2, scale: scale), y: align(top, scale: scale))
        context.rotate(by: .pi / 2)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: 0, y: align(-font.ascender, scale: scale))
        CTLineDraw(line, context)
        context.restoreGState()
        _ = width
    }

    private func line(_ text: String, font: NSFont) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
    }

    private func align(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }
}
