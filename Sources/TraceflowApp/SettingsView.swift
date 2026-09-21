import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section("常规") {
                Toggle("显示 HUD", isOn: $model.isHUDVisible)
                Picker("轮播间隔", selection: $model.displayDuration) { Text("3 秒").tag(3.0); Text("5 秒").tag(5.0); Text("10 秒").tag(10.0) }
                Picker("光晕强度", selection: $model.glowStrength) { Text("低").tag(0); Text("中").tag(1); Text("高").tag(2) }
                Button("恢复 HUD 默认位置") { model.resetHUDPosition() }
            }
            Section("Codex Hooks") {
                HStack { Circle().fill(healthColor).frame(width: 10, height: 10); Text(healthTitle); Spacer(); Text(model.hooksHealth.detail).foregroundStyle(.secondary) }
                Text("安装、修复与移除操作将在下一阶段接入。").font(.caption).foregroundStyle(.secondary)
            }
            Section("会话") {
                if model.sessions.isEmpty { Text("尚未发现会话").foregroundStyle(.secondary) }
                ForEach(model.sessions) { session in
                    HStack {
                        Toggle("", isOn: Binding(get: { session.persisted.isIncludedInHUD }, set: { model.setIncluded($0, sessionID: session.id) })).labelsHidden()
                        VStack(alignment: .leading) { Text(session.displayTitle); Text("\(session.persisted.projectPath ?? "未知路径") · \(String(session.id.prefix(8))) · \(session.persisted.lastUpdatedAt.formatted())").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer(); Text(session.state.rawValue).foregroundStyle(.secondary)
                        Button(role: .destructive) { model.deleteSession(session.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
                if !model.sessions.isEmpty { Button("清空全部记录", role: .destructive) { model.clearSessions() } }
            }
            Section("诊断") {
                Button("打开日志目录") { model.openLogsDirectory() }
                Button("清除日志", role: .destructive) { model.clearLogs() }
            }
        }.formStyle(.grouped).padding().frame(minWidth: 540, minHeight: 480)
    }

    private var healthTitle: String { switch model.hooksHealth.state { case .notInstalled: "未安装"; case .pendingVerification: "待验证"; case .healthy: "正常"; case .error: "异常" } }
    private var healthColor: Color { switch model.hooksHealth.state { case .notInstalled: .gray; case .pendingVerification: .yellow; case .healthy: .green; case .error: .red } }
}
