import SwiftUI
import TraceflowCore

struct HUDView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presentation: HUDWindowPresentation
    // Layout belongs to this window's lifetime. The model can publish the next
    // layout before the controller retires this hosting tree on the main queue.
    let style: HUDDisplayStyle
    let layout: HUDLayoutMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(model: AppModel) {
        self.init(model: model, layout: model.hudLayoutMode,
                  presentation: HUDWindowPresentation(model: model))
    }

    init(model: AppModel, layout: HUDLayoutMode, style: HUDDisplayStyle? = nil, presentation: HUDWindowPresentation) {
        _model = ObservedObject(wrappedValue: model)
        _presentation = ObservedObject(wrappedValue: presentation)
        self.layout = layout
        self.style = style ?? model.hudDisplayStyle
    }

    // displayTitle includes the project prefix; the HUD shows only the session.
    var displayedTitle: String {
        presentation.displayedSession?.sessionListTitle ?? "Traceflow"
    }

    var body: some View {
        Group {
            switch layout {
            case .horizontalLeft, .horizontalRight: horizontalContent
            case .verticalTop, .verticalBottom: verticalContent
            }
        }
        .frame(width: layout.isHorizontal ? (style == .compact ? HUDMetrics.compactLongAxis : 380 + 40 * model.hudIconFraction) : HUDMetrics.shortAxis,
               height: layout.isHorizontal ? HUDMetrics.shortAxis : (style == .compact ? HUDMetrics.compactLongAxis : 380 + 40 * model.hudIconFraction))
        .overlay(Capsule().stroke(.white.opacity((colorScheme == .dark ? 0.16 : 0.24) * HUDBackgroundAppearance(model.hudBackgroundTransparency).backgroundAlpha), lineWidth: 0.5))
        .contentShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var horizontalContent: some View {
        HStack(spacing: 0) {
            ForEach(layout.regions) { region in
                switch region {
                case .lights:
                    HStack(spacing: HUDMetrics.lightSpacing) { lights }
                        .frame(width: HUDMetrics.lightAreaLength, height: HUDMetrics.shortAxis)
                case .icon:
                    if style == .compact {
                        SessionMarkerView(colorHex: presentation.displayedSession?.persisted.markerColorHex)
                            .frame(width: HUDMetrics.iconLength, height: HUDMetrics.shortAxis)
                    } else {
                        icon.opacity(model.hudIconFraction)
                            .frame(width: HUDMetrics.iconLength * model.hudIconFraction, height: HUDMetrics.shortAxis).clipped()
                    }
                case .title:
                    if style == .standard { titleRegion(vertical: false) }
                }
            }
        }
    }

    private var verticalContent: some View {
        VStack(spacing: 0) {
            ForEach(layout.regions) { region in
                switch region {
                case .lights:
                    VStack(spacing: HUDMetrics.lightSpacing) { lights }
                        .frame(width: HUDMetrics.shortAxis, height: HUDMetrics.lightAreaLength)
                case .icon:
                    if style == .compact {
                        SessionMarkerView(colorHex: presentation.displayedSession?.persisted.markerColorHex)
                            .frame(width: HUDMetrics.iconLength, height: HUDMetrics.shortAxis)
                    } else {
                        icon.opacity(model.hudIconFraction)
                            .frame(width: HUDMetrics.shortAxis, height: HUDMetrics.iconLength * model.hudIconFraction).clipped()
                    }
                case .title:
                    if style == .standard { titleRegion(vertical: true) }
                }
            }
        }
    }

    private var icon: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 17, weight: .semibold))
    }

    @ViewBuilder
    private func titleRegion(vertical: Bool) -> some View {
        Group {
            if let session = presentation.displayedSession {
                ZStack {
                    // Snapshot the text so outgoing content never reads a new
                    // placeholder from the model during a transition.
                    titleContent(session.sessionListTitle, vertical: vertical)
                        .id(session.id)
                        .transition(titleTransition(vertical: vertical))
                }
                .transaction { $0.animation = titleAnimation }
            } else {
                // The default name is static and cannot become an outgoing session.
                titleContent("Traceflow", vertical: vertical)
            }
        }
        .frame(width: vertical ? HUDMetrics.shortAxis : HUDMetrics.titleLength + HUDMetrics.separatorThickness * 2,
               height: vertical ? HUDMetrics.titleLength + HUDMetrics.separatorThickness * 2 : HUDMetrics.shortAxis)
        .clipped()
    }

    @ViewBuilder
    private func titleContent(_ text: String, vertical: Bool) -> some View {
        if vertical {
            VerticalMixedTitleView(title: text, color: model.hudTitleColor)
                .frame(width: HUDMetrics.shortAxis, height: HUDMetrics.titleLength)
        } else {
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(model.hudTitleColor == .white ? Color.white : Color.black)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: HUDMetrics.titleTextLength, alignment: .leading)
        }
    }

    private var accessibilityDescription: String {
        let title = displayedTitle
        let state: String
        switch presentation.displayedSession?.state {
        case .attention: state = "需要处理"
        case .running: state = "运行中"
        case .completed: state = "已完成"
        case .idle: state = "待机"
        case nil: state = "没有参与显示的会话"
        }
        return "\(title)，\(state)"
    }

    @ViewBuilder private var lights: some View {
        StatusLight(kind: .attention, active: presentation.displayedSession?.state == .attention, glow: model.hudGlowMode, reduceMotion: reduceMotion)
        StatusLight(kind: .completed, active: presentation.displayedSession?.state == .completed, glow: model.hudGlowMode, reduceMotion: reduceMotion)
        StatusLight(kind: .running, active: presentation.displayedSession?.state == .running, glow: model.hudGlowMode, reduceMotion: reduceMotion)
    }

    private func titleTransition(vertical: Bool) -> AnyTransition {
        switch HUDTitleTransition.style(shouldAnimate: model.shouldAnimateDisplayChange, reduceMotion: reduceMotion) {
        case .none:
            return .identity
        case .fade:
            return .opacity
        case .slide:
            return .asymmetric(
                insertion: .move(edge: vertical ? .leading : .bottom).combined(with: .opacity),
                removal: .move(edge: vertical ? .trailing : .top).combined(with: .opacity)
            )
        }
    }

    private var titleAnimation: Animation? {
        switch HUDTitleTransition.style(shouldAnimate: model.shouldAnimateDisplayChange, reduceMotion: reduceMotion) {
        case .none: nil
        // A short decelerating transition feels responsive and remains smooth
        // when SwiftUI interrupts it for a newer carousel decision.
        case .slide: .easeOut(duration: HUDTitleTransition.maximumDuration)
        case .fade: .easeInOut(duration: 0.15)
        }
    }

}

enum StatusLightKind {
    case attention
    case running
    case completed

    var color: Color {
        switch self {
        case .attention: .red
        case .running: .green
        case .completed: .yellow
        }
    }

    var runtimeState: SessionRuntimeState {
        switch self {
        case .attention: .attention
        case .running: .running
        case .completed: .completed
        }
    }
}

private struct StatusLight: View {
    let kind: StatusLightKind
    let active: Bool
    let glow: HUDGlowMode
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active || reduceMotion)) { timeline in
            let visual = HUDLightAnimation.parameters(
                for: kind.runtimeState,
                isActive: active,
                referenceTime: timeline.date.timeIntervalSinceReferenceDate,
                reduceMotion: reduceMotion
            )
            StatusLightFrame(kind: kind, active: active, glow: glow, visual: visual)
        }
        .accessibilityHidden(true)
    }
}

/// A single sampled animation frame, shared by the live timeline and native rendering checks.
struct StatusLightFrame: View {
    let kind: StatusLightKind
    let active: Bool
    let glow: HUDGlowMode
    let visual: HUDLightVisualParameters

    private var bodyRadius: CGFloat {
        let base = HUDMetrics.lightDiameter / 2
        return active ? base * CGFloat(visual.scale) : base
    }

    private var bodyOpacity: Double { active ? visual.bodyOpacity : 0.18 }
    private var haloProgress: Double { active ? min(1, max(0, visual.glowIntensity)) : 0 }
    private var haloWidth: CGFloat { (glow == .strong ? 7 : 4) * CGFloat(haloProgress) }

    var body: some View {
        ZStack {
            if active && haloProgress > 0 {
                synchronizedHalo
            }
            Circle()
                .fill(kind.color.opacity(bodyOpacity))
                .frame(width: bodyRadius * 2, height: bodyRadius * 2)
        }
        .frame(width: HUDMetrics.lightDiameter, height: HUDMetrics.lightDiameter)
        .accessibilityHidden(true)
    }

    private var synchronizedHalo: some View {
        let radius = bodyRadius
        let width = haloWidth
        let outer = radius + width
        let inner = max(0, radius - 1)
        let q = haloProgress
        let strong = glow == .strong
        // Strong peaks already include the approved 30% reduction.
        let edge: Double = strong ? 0.63 : 0.35
        let near: Double = strong ? 0.56 : 0.28
        let far: Double = strong ? 0.175 : 0.12

        return Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: inner / outer),
                    .init(color: kind.color.opacity(edge * q), location: radius / outer),
                    .init(color: kind.color.opacity(near * q), location: (radius + 0.28 * width) / outer),
                    .init(color: kind.color.opacity(far * q), location: (radius + 0.60 * width) / outer),
                    .init(color: .clear, location: 1)
                ],
                center: .center,
                startRadius: 0,
                endRadius: outer
            ))
            .frame(width: outer * 2, height: outer * 2)
    }
}
