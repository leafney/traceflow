import SwiftUI
import TraceflowCore

struct HUDView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch model.hudLayoutMode {
            case .horizontal: horizontalContent
            case .vertical: verticalContent
            }
        }
        .frame(width: model.hudLayoutMode == .horizontal ? HUDMetrics.longAxis : HUDMetrics.shortAxis,
               height: model.hudLayoutMode == .horizontal ? HUDMetrics.shortAxis : HUDMetrics.longAxis)
        .background(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.24), lineWidth: 0.5))
        .contentShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .animation(.easeInOut(duration: 0.25), value: model.displayedSession?.id)
    }

    private var horizontalContent: some View {
        HStack(spacing: 0) {
            icon.frame(width: HUDMetrics.iconLength, height: HUDMetrics.shortAxis)
            horizontalSeparator
            ZStack {
                title
                    .frame(width: HUDMetrics.titleTextLength, alignment: .leading)
                    .id(model.displayedSession?.id ?? "placeholder")
                    .transition(titleTransition(vertical: false))
            }
            .frame(width: HUDMetrics.titleLength, height: HUDMetrics.shortAxis)
            .clipped()
            horizontalSeparator
            HStack(spacing: HUDMetrics.lightSpacing) { lights }
                .frame(width: HUDMetrics.lightAreaLength, height: HUDMetrics.shortAxis)
        }
    }

    private var verticalContent: some View {
        VStack(spacing: 0) {
            icon.frame(width: HUDMetrics.shortAxis, height: HUDMetrics.iconLength)
            verticalSeparator
            ZStack {
                title
                    .frame(width: HUDMetrics.titleTextLength, height: 20, alignment: .leading)
                    .rotationEffect(.degrees(90))
                    .frame(width: HUDMetrics.shortAxis, height: HUDMetrics.titleLength)
                    .id(model.displayedSession?.id ?? "placeholder")
                    .transition(titleTransition(vertical: true))
            }
            .frame(width: HUDMetrics.shortAxis, height: HUDMetrics.titleLength)
            .clipped()
            verticalSeparator
            VStack(spacing: HUDMetrics.lightSpacing) { lights }
                .frame(width: HUDMetrics.shortAxis, height: HUDMetrics.lightAreaLength)
        }
    }

    private var icon: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 17, weight: .semibold))
    }

    private var title: some View {
        Text(model.displayedSession?.displayTitle ?? "Traceflow")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var accessibilityDescription: String {
        let title = model.displayedSession?.displayTitle ?? "Traceflow"
        let state: String
        switch model.displayedSession?.state {
        case .attention: state = "需要处理"
        case .running: state = "运行中"
        case .completed: state = "已完成"
        case .idle: state = "待机"
        case nil: state = "没有参与显示的会话"
        }
        return "\(title)，\(state)"
    }

    @ViewBuilder private var lights: some View {
        StatusLight(kind: .attention, active: model.displayedSession?.state == .attention, glow: model.hudGlowMode, reduceMotion: reduceMotion)
        StatusLight(kind: .running, active: model.displayedSession?.state == .running, glow: model.hudGlowMode, reduceMotion: reduceMotion)
        StatusLight(kind: .completed, active: model.displayedSession?.state == .completed, glow: model.hudGlowMode, reduceMotion: reduceMotion)
    }

    private func titleTransition(vertical: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: vertical ? .leading : .bottom),
            removal: .move(edge: vertical ? .trailing : .top)
        )
    }

    private var separatorColor: Color {
        .white.opacity(colorScheme == .dark ? 0.12 : 0.18)
    }

    private var horizontalSeparator: some View {
        Rectangle().fill(separatorColor).frame(width: HUDMetrics.separatorThickness, height: 22)
            .frame(width: HUDMetrics.separatorThickness, height: HUDMetrics.shortAxis)
    }

    private var verticalSeparator: some View {
        Rectangle().fill(separatorColor).frame(width: 22, height: HUDMetrics.separatorThickness)
            .frame(width: HUDMetrics.shortAxis, height: HUDMetrics.separatorThickness)
    }
}

private enum StatusLightKind {
    case attention
    case running
    case completed

    var color: Color {
        switch self {
        case .attention: .red
        case .running: .yellow
        case .completed: .green
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
            let phase = animationPhase(at: timeline.date)
            let intensity = activeOpacity(phase: phase)
            let parameters = GlowParameters(mode: glow)
            let scale = reduceMotion ? 1.0 : 1.0 + phase * (parameters.maximumScale - 1.0)

            ZStack {
                if active {
                    glowLayer(diameter: 40, blurRadius: parameters.outerBlur,
                              peakOpacity: parameters.outerOpacity, intensity: intensity)
                        .scaleEffect(scale)
                    glowLayer(diameter: 34, blurRadius: parameters.innerBlur,
                              peakOpacity: parameters.innerOpacity, intensity: intensity)
                        .scaleEffect(scale)
                }
                Circle()
                    .fill(kind.color.opacity(active ? intensity : 0.18))
                    .frame(width: HUDMetrics.lightDiameter, height: HUDMetrics.lightDiameter)
            }
            .frame(width: HUDMetrics.lightDiameter, height: HUDMetrics.lightDiameter)
        }
        .accessibilityHidden(true)
    }

    private func glowLayer(diameter: CGFloat, blurRadius: CGFloat, peakOpacity: Double, intensity: Double) -> some View {
        Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: kind.color.opacity(peakOpacity * intensity), location: 0),
                    .init(color: kind.color.opacity(peakOpacity * intensity * 0.58), location: 0.30),
                    .init(color: .clear, location: 0.58)
                ],
                center: .center,
                startRadius: 0,
                endRadius: diameter / 2
            ))
            .frame(width: diameter, height: diameter)
            .blur(radius: blurRadius)
    }

    private func animationPhase(at date: Date) -> Double {
        guard active, !reduceMotion else { return 1 }
        let period: Double
        switch kind {
        case .attention: period = 0.56
        case .running: period = 2.30
        case .completed: period = 2.80
        }
        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        if kind == .attention {
            switch progress {
            case 0..<0.15: return progress / 0.15
            case 0.15..<0.55: return 1
            case 0.55..<0.70: return 1 - (progress - 0.55) / 0.15
            default: return 0
            }
        }
        return (sin(progress * 2 * .pi - .pi / 2) + 1) / 2
    }

    private func activeOpacity(phase: Double) -> Double {
        guard active, !reduceMotion else { return active ? 1 : 0.18 }
        switch kind {
        case .attention: return 0.35 + phase * 0.65
        case .running: return 0.65 + phase * 0.35
        case .completed: return 1
        }
    }
}

private struct GlowParameters {
    let maximumScale: CGFloat
    let innerBlur: CGFloat
    let innerOpacity: Double
    let outerBlur: CGFloat
    let outerOpacity: Double

    init(mode: HUDGlowMode) {
        switch mode {
        case .standard:
            maximumScale = 1.15
            innerBlur = 6
            innerOpacity = 0.50
            outerBlur = 12
            outerOpacity = 0.28
        case .strong:
            maximumScale = 1.30
            innerBlur = 9
            innerOpacity = 0.70
            outerBlur = 18
            outerOpacity = 0.45
        }
    }
}
