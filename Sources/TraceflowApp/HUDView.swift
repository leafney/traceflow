import SwiftUI
import TraceflowCore

struct HUDView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold)).frame(width: 44)
            Divider().frame(height: 24)
            ZStack {
                Text(model.displayedSession?.displayTitle ?? "Traceflow")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                    .id(model.displayedSession?.id ?? "placeholder")
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .top)))
            }.padding(.horizontal, 12)
            Divider().frame(height: 24)
            HStack(spacing: 10) {
                StatusLight(color: .red, active: model.displayedSession?.state == .attention, pulsing: true, glow: model.glowStrength, reduceMotion: reduceMotion)
                StatusLight(color: .yellow, active: model.displayedSession?.state == .running, pulsing: true, glow: model.glowStrength, reduceMotion: reduceMotion)
                StatusLight(color: .green, active: model.displayedSession?.state == .completed, pulsing: false, glow: model.glowStrength, reduceMotion: reduceMotion)
            }.frame(width: 98)
        }
        .frame(width: 420, height: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
        .contentShape(Capsule())
        .animation(.easeInOut(duration: 0.25), value: model.displayedSession?.id)
    }
}

private struct StatusLight: View {
    let color: Color; let active: Bool; let pulsing: Bool; let glow: Int; let reduceMotion: Bool
    @State private var phase = false
    var body: some View {
        Circle().fill(active ? color : Color.primary.opacity(0.12)).frame(width: 12, height: 12)
            .shadow(color: active ? color.opacity([0.3, 0.5, 0.75][min(2, max(0, glow))]) : .clear, radius: active ? [3, 6, 9][min(2, max(0, glow))] : 0)
            .opacity(active && pulsing && !reduceMotion ? (phase ? 0.5 : 1) : 1)
            .scaleEffect(active && pulsing && !reduceMotion ? (phase ? 0.92 : 1.08) : 1)
            .onAppear { if pulsing && !reduceMotion { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { phase = true } } }
    }
}
