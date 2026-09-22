import SwiftUI
import TraceflowCore

struct HUDView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40)
            separator
            ZStack {
                Text(model.displayedSession?.displayTitle ?? "Traceflow")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(model.displayedSession?.id ?? "placeholder")
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .top)))
            }
            .padding(.horizontal, 8)
            separator
            HStack(spacing: 8) {
                StatusLight(kind: .attention, active: model.displayedSession?.state == .attention, glow: model.hudGlowMode == .strong ? 2 : 1, reduceMotion: reduceMotion)
                StatusLight(kind: .running, active: model.displayedSession?.state == .running, glow: model.hudGlowMode == .strong ? 2 : 1, reduceMotion: reduceMotion)
                StatusLight(kind: .completed, active: model.displayedSession?.state == .completed, glow: model.hudGlowMode == .strong ? 2 : 1, reduceMotion: reduceMotion)
            }
            .frame(width: 104)
        }
        .frame(width: 420, height: 40)
        .background(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.24), lineWidth: 0.5))
        .contentShape(Capsule())
        .animation(.easeInOut(duration: 0.25), value: model.displayedSession?.id)
    }

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(colorScheme == .dark ? 0.12 : 0.18))
            .frame(width: 0.5, height: 22)
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
    let glow: Int
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active || reduceMotion || kind == .completed)) { timeline in
            let phase = animationPhase(at: timeline.date)
            Circle()
                .fill(kind.color.opacity(active ? activeOpacity(phase: phase) : 0.18))
                .frame(width: 20, height: 20)
                .scaleEffect(active ? activeScale(phase: phase) : 1)
                .shadow(
                    color: active ? kind.color.opacity(glowOpacity * activeOpacity(phase: phase)) : .clear,
                    radius: active ? glowRadius : 0
                )
        }
        .accessibilityHidden(true)
    }

    private func animationPhase(at date: Date) -> Double {
        guard active, !reduceMotion else { return 1 }
        let period = kind == .attention ? 0.56 : 2.30
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

    private func activeScale(phase: Double) -> Double {
        guard active, !reduceMotion, kind == .running else { return 1 }
        return 0.94 + phase * 0.12
    }

    private var glowRadius: CGFloat { [4, 7, 10][min(2, max(0, glow))] }
    private var glowOpacity: Double { [0.35, 0.52, 0.70][min(2, max(0, glow))] }
}
