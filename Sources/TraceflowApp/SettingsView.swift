import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section("常规") {
                Toggle("显示 HUD", isOn: $model.isHUDVisible)
                Picker("轮播间隔", selection: $model.displayDuration) { Text("3 秒").tag(3.0); Text("5 秒").tag(5.0); Text("10 秒").tag(10.0) }
                Picker("光晕强度", selection: $model.glowStrength) { Text("低").tag(0); Text("中").tag(1); Text("高").tag(2) }
            }
            Section("Codex Hooks") { Text("Hooks 管理将在阶段 5 接入").foregroundStyle(.secondary) }
            Section("会话") {
                if model.sessions.isEmpty { Text("尚未发现会话").foregroundStyle(.secondary) }
                ForEach(model.sessions) { session in
                    HStack { Image(systemName: session.persisted.isIncludedInHUD ? "checkmark.square.fill" : "square"); Text(session.displayTitle); Spacer(); Text(session.state.rawValue).foregroundStyle(.secondary) }
                }
            }
        }.formStyle(.grouped).padding().frame(minWidth: 540, minHeight: 480)
    }
}
