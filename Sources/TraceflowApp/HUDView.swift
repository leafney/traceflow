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
        .frame(width: model.hudLayoutMode == .horizontal ? 420 : 40,
               height: model.hudLayoutMode == .horizontal ? 40 : 420)
        .background(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.24), lineWidth: 0.5))
        .contentShape(Capsule())
        .animation(.easeInOut(duration: 0.25), value: model.displayedSession?.id)
    }

    private var horizontalContent: some View {
        HStack(spacing: 0) {
            icon.frame(width: 40, height: 40)
            horizontalSeparator
            ZStack {
                title
                    .frame(width: 263, alignment: .leading)
                    .id(model.displayedSession?.id ?? "placeholder")
                    .transition(titleTransition(vertical: false))
            }
            .frame(width: 275, height: 40)
            .clipped()
            horizontalSeparator
            HStack(spacing: 4) { lights }
                .frame(width: 104, height: 40)
        }
    }

    private var verticalContent: some View {
        VStack(spacing: 0) {
            icon.frame(width: 40, height: 40)
            verticalSeparator
            ZStack {
                title
                    .frame(width: 263, height: 20, alignment: .leading)
                    .rotationEffect(.degrees(90))
                    .frame(width: 40, height: 275)
                    .id(model.displayedSession?.id ?? "placeholder")
                    .transition(titleTransition(vertical: true))
            }
            .frame(width: 40, height: 275)
            .clipped()
            verticalSeparator
            VStack(spacing: 4) { lights }
                .frame(width: 40, height: 104)
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
        Rectangle().fill(separatorColor).frame(width: 0.5, height: 22)
            .frame(width: 0.5, height: 40)
    }

    private var verticalSeparator: some View {
        Rectangle().fill(separatorColor).frame(width: 22, height: 0.5)
            .frame(width: 40, height: 0.5)
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
            let scale = reduceMotion ? 1.0 : 1.0 + phase * (glow == .strong ? 0.30 : 0.15)

            Circle()
                .fill(kind.color.opacity(active ? intensity : 0.18))
                .frame(width: 28, height: 28)
                .background {
                    if active {
                        glowLayer(diameter: 52, peakOpacity: glow == .strong ? 0.45 : 0.28, intensity: intensity)
                            .scaleEffect(scale)
                        glowLayer(diameter: 40, peakOpacity: glow == .strong ? 0.70 : 0.50, intensity: intensity)
                            .scaleEffect(scale)
                    }
                }
                .shadow(color: active ? kind.color.opacity((glow == .strong ? 0.70 : 0.50) * intensity) : .clear,
                        radius: active ? (glow == .strong ? 9 : 6) : 0)
        }
        .accessibilityHidden(true)
    }

    private func glowLayer(diameter: CGFloat, peakOpacity: Double, intensity: Double) -> some View {
        Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: kind.color.opacity(peakOpacity * intensity), location: 0),
                    .init(color: kind.color.opacity(peakOpacity * intensity * 0.58), location: 0.32),
                    .init(color: .clear, location: 0.62)
                ],
                center: .center,
                startRadius: 0,
                endRadius: diameter / 2
            ))
            .frame(width: diameter, height: diameter)
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
