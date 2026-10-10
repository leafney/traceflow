import AppKit
import CoreText
import TraceflowCore

/// Immutable full-text layout. Measurement and rendering share the same glyphs.
final class HUDTitleTextLayout {
    struct Run {
        let segment: VerticalTitleSegment
        let line: CTLine?
        let advance: CGFloat
        let scale: CGFloat
        let inkBounds: CGRect
        let baselineOffset: CGFloat
        let centerOffset: CGFloat
    }
    let title: String
    let vertical: Bool
    let backingScale: CGFloat
    let font: NSFont
    let line: CTLine
    let runs: [Run]
    let length: CGFloat
    private let truncatedLine: CTLine
    private let staticRuns: [Run]
    private let verticalEllipsis: Bool
    static let viewport = HUDMetrics.mediumTextLength

    init(title: String, vertical: Bool, backingScale: CGFloat = 2) {
        self.title = title
        self.vertical = vertical
        self.backingScale = backingScale
        let base = NSFont.systemFont(ofSize: 13, weight: .medium)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 13) } ?? base
        self.font = font
        func makeLine(_ text: String) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                .font: font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
            ]))
        }
        let line = makeLine(title)
        self.line = line
        let ellipsis = makeLine("…")
        truncatedLine = CTLineCreateTruncatedLine(line, Double(Self.viewport), .end, ellipsis) ?? ellipsis
        let hanAdvance = ceil((font.ascender - font.descender + font.leading) * backingScale) / backingScale
        func makeRun(_ segment: VerticalTitleSegment) -> Run {
            let text: String
            let rotated: Bool
            switch segment {
            case .gap: return Run(segment: segment, line: nil, advance: 4, scale: 1, inkBounds: .zero, baselineOffset: 0, centerOffset: 0)
            case let .han(c), let .upright(c): text = String(c); rotated = false
            case let .latin(s): text = s; rotated = true
            }
            let ctLine = makeLine(text)
            let ink = CTLineGetBoundsWithOptions(ctLine, .useGlyphPathBounds)
            let width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            let cross = rotated ? ink.height : max(width, ink.width)
            let scale = cross > HUDMetrics.shortAxis ? HUDMetrics.shortAxis / cross : 1
            let padding = 1 / backingScale
            let baseline: CGFloat
            switch segment {
            case .upright: baseline = ink.maxY + padding / scale
            default: baseline = max(font.ascender, ink.maxY + padding / scale)
            }
            let advance = rotated ? width * scale : max(hanAdvance * scale, (baseline - ink.minY) * scale + padding)
            return Run(segment: segment, line: ctLine, advance: advance, scale: scale, inkBounds: ink,
                       baselineOffset: baseline * scale, centerOffset: (rotated ? ink.midY : ink.midX) * scale)
        }
        let segments = VerticalTitleParser.segments(for: title, preserveUnsupportedCharacters: true)
        let runs = segments.map(makeRun)
        self.runs = runs
        length = vertical ? runs.reduce(0) { $0 + $1.advance } : CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let staticLayout = VerticalTitleMeasurer.layout(segments: segments, maximumLength: Double(Self.viewport), ellipsisAdvance: 12,
                                                       advance: { Double(makeRun($0).advance) })
        staticRuns = staticLayout.visibleSegments.map(makeRun)
        verticalEllipsis = staticLayout.showsEllipsis
    }

    /// Context uses a flipped NSView coordinate system, with origin at the text viewport.
    func draw(in context: CGContext, offset: CGFloat, color: NSColor, reduceMotion: Bool = false) {
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: vertical ? HUDMetrics.shortAxis : Self.viewport,
                               height: vertical ? Self.viewport : HUDMetrics.shortAxis))
        context.setFillColor(color.cgColor)
        let overflows = length > Self.viewport
        let positions: [CGFloat] = overflows && !reduceMotion ? [offset, offset + length + CGFloat(HUDTitleMarqueeState.gap)] : [0]
        for position in positions {
            if vertical {
                var cursor = position
                for run in reduceMotion ? staticRuns : runs {
                    if let line = run.line { drawVertical(run, line: line, top: cursor, in: context) }
                    cursor += run.advance
                }
                if reduceMotion && verticalEllipsis {
                    for index in 0..<3 {
                        context.fillEllipse(in: CGRect(x: 18.8, y: cursor + CGFloat(index) * 4.2, width: 2.4, height: 2.4))
                    }
                }
            } else {
                context.saveGState()
                context.translateBy(x: position, y: HUDMetrics.shortAxis / 2 + (font.ascender + font.descender) / 2)
                context.scaleBy(x: 1, y: -1)
                context.textMatrix = .identity
                context.textPosition = .zero
                CTLineDraw(reduceMotion && overflows ? truncatedLine : line, context)
                context.restoreGState()
            }
        }
        context.restoreGState()
    }

    private func drawVertical(_ run: Run, line: CTLine, top: CGFloat, in context: CGContext) {
        context.saveGState()
        switch run.segment {
        case .latin:
            context.translateBy(x: HUDMetrics.shortAxis / 2 - run.centerOffset, y: top)
            context.scaleBy(x: run.scale, y: -run.scale)
            context.rotate(by: -.pi / 2)
        default:
            context.translateBy(x: HUDMetrics.shortAxis / 2 - run.centerOffset, y: top + run.baselineOffset)
            context.scaleBy(x: run.scale, y: -run.scale)
        }
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
