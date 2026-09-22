import SwiftUI
import TraceflowCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmation: DestructiveConfirmation?

    var body: some View {
        Form {
            Section("常规") {
                Toggle("显示 HUD", isOn: $model.isHUDVisible)
                Picker("轮播间隔", selection: $model.displayDuration) { Text("3 秒").tag(3.0); Text("5 秒").tag(5.0); Text("10 秒").tag(10.0) }
                Picker("光晕强度", selection: $model.glowStrength) { Text("低").tag(0); Text("中").tag(1); Text("高").tag(2) }
                Button("恢复 HUD 默认位置") { model.resetHUDPosition() }
            }
            Section("Codex Hooks") {
                healthRow(label: "Hooks 配置", color: hooksHealthColor, state: hooksHealthTitle, detail: model.hooksHealth.detail)
                healthRow(label: "本地通信", color: communicationHealthColor, state: communicationHealthTitle, detail: model.localCommunicationHealth.detail)
                healthRow(label: "会话数据", color: sessionDataHealthColor, state: sessionDataHealthTitle, detail: sessionDataHealthDetail)
                HStack {
                    Button("安装/修复 Hooks") { model.installHooks() }
                    Button("测试转发通道") { model.verifyHooksConnection() }.disabled(model.isVerifyingHooks)
                    if model.isVerifyingHooks { ProgressView().controlSize(.small) }
                    Button("移除 Hooks", role: .destructive) { model.removeHooks() }
                }
                if let message = model.hooksActionMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                sessionDataRecoveryActions
            }
            Section("会话") {
                HStack {
                    Button("同步 Codex 会话") { model.syncCodexSessions() }
                        .disabled(model.isSyncingSessions || !model.sessionDataHealth.allowsSaving)
                    if model.isSyncingSessions { ProgressView().controlSize(.small) }
                }
                if let message = model.sessionSyncMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                if model.sessionProjects.isEmpty { Text("尚未发现会话").foregroundStyle(.secondary) }
                ForEach(model.sessionProjects) { project in
                    projectHeader(project)
                    if model.expandedProjectKeys.contains(project.id) {
                        ForEach(project.sessions) { session in
                            sessionRow(session)
                                .padding(.leading, 24)
                        }
                    }
                }
                if !model.sessions.isEmpty {
                    Button("清空全部记录", role: .destructive) {
                        confirmation = DestructiveConfirmation(kind: .clearAll)
                    }
                    .disabled(!model.sessionDataHealth.allowsSaving)
                }
            }
            Section("诊断") {
                Button("打开日志目录") { model.openLogsDirectory() }
                Button("清除日志", role: .destructive) { model.clearLogs() }
            }
        }
        .formStyle(.grouped).padding().frame(minWidth: 680, minHeight: 600)
        .alert(item: $confirmation) { item in
            switch item.kind {
            case let .deleteSession(id, _):
                Alert(
                    title: Text("删除此会话记录？"),
                    message: Text("仅删除 Traceflow 本地记录，不会删除 Codex 中的原始对话。"),
                    primaryButton: .destructive(Text("删除记录")) { model.deleteSession(id) },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .clearAll:
                Alert(
                    title: Text("清空全部会话记录？"),
                    message: Text("将删除 Traceflow 保存的全部本地会话记录和 HUD 选择，不会删除 Codex 中的原始对话。"),
                    primaryButton: .destructive(Text("清空全部")) { model.clearSessions() },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
    }

    private func healthRow(label: String, color: Color, state: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).frame(width: 72, alignment: .leading)
            Text(state).fontWeight(.medium)
            Spacer()
            Text(detail).foregroundStyle(.secondary).lineLimit(1).help(detail)
        }
    }

    @ViewBuilder
    private var sessionDataRecoveryActions: some View {
        switch model.sessionDataHealth {
        case .healthy:
            EmptyView()
        case .corrupted:
            HStack {
                Button("打开数据目录") { model.openSessionDataDirectory() }
                Button("备份并重建") { model.backupAndRebuildSessions() }
                    .disabled(model.isRebuildingSessions)
                if model.isRebuildingSessions { ProgressView().controlSize(.small) }
            }
        case .unwritable:
            HStack {
                Button("打开数据目录") { model.openSessionDataDirectory() }
                Button("重试保存") { model.retrySessionSave() }
            }
        }
    }

    @ViewBuilder
    private func projectHeader(_ project: SessionProjectGroup) -> some View {
        let expanded = model.expandedProjectKeys.contains(project.id)
        HStack(spacing: 10) {
            Button {
                model.setProjectExpanded(!expanded, projectKey: project.id)
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(expanded ? "收起项目 \(project.displayName)" : "展开项目 \(project.displayName)")

            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName).fontWeight(.semibold).lineLimit(1).help(project.displayName)
                Text(project.projectPath ?? "未知路径").font(.caption).foregroundStyle(.secondary).lineLimit(1).help(project.projectPath ?? "未知路径")
            }
            Spacer(minLength: 8)
            Text("已启用 \(project.enabledCount) / \(project.totalCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Menu("批量操作") {
                Button("全部启用") { model.setProjectIncluded(true, projectKey: project.id) }
                    .disabled(project.selectionState == .all)
                Button("全部关闭") { model.setProjectIncluded(false, projectKey: project.id) }
                    .disabled(project.selectionState == .none)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("项目 \(project.displayName) 批量操作")
            .disabled(!model.sessionDataHealth.allowsSaving)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sessionRow(_ session: SessionSnapshot) -> some View {
        let title = sessionListTitle(session)
        HStack(spacing: 10) {
            Toggle("参与 HUD", isOn: Binding(
                get: { session.persisted.isIncludedInHUD },
                set: { model.setIncluded($0, sessionID: session.id) }
            ))
            .labelsHidden()
            .disabled(!model.sessionDataHealth.allowsSaving)
            .accessibilityLabel("\(title) 参与 HUD")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1).help(title)
                Text("\(String(session.id.prefix(8))) · \(session.persisted.lastUpdatedAt.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(runtimeStateTitle(session.state)).foregroundStyle(.secondary)
            Button(role: .destructive) {
                confirmation = DestructiveConfirmation(kind: .deleteSession(id: session.id, title: title))
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除会话 \(title)")
            .disabled(!model.sessionDataHealth.allowsSaving)
        }
    }

    private func sessionListTitle(_ session: SessionSnapshot) -> String {
        let value = session.conversationSummary ?? session.persisted.codexThreadName
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "未命名会话" : trimmed
    }

    private func runtimeStateTitle(_ state: SessionRuntimeState) -> String {
        switch state {
        case .idle: "待机"
        case .running: "执行中"
        case .attention: "等待权限"
        case .completed: "已完成"
        }
    }

    private var hooksHealthTitle: String { switch model.hooksHealth.state { case .notInstalled: "未安装"; case .needsRepair: "需要修复"; case .pendingVerification: "待验证"; case .healthy: "正常"; case .error: "异常" } }
    private var hooksHealthColor: Color { switch model.hooksHealth.state { case .notInstalled: .gray; case .needsRepair, .error: .red; case .pendingVerification: .yellow; case .healthy: .green } }
    private var communicationHealthTitle: String { switch model.localCommunicationHealth.state { case .healthy: "正常"; case .testing: "测试中"; case .error: "异常" } }
    private var communicationHealthColor: Color { switch model.localCommunicationHealth.state { case .healthy: .green; case .testing: .yellow; case .error: .red } }
    private var sessionDataHealthTitle: String { switch model.sessionDataHealth { case .healthy: "正常"; case .corrupted: "已损坏"; case .unwritable: "无法写入" } }
    private var sessionDataHealthColor: Color { switch model.sessionDataHealth { case .healthy: .green; case .corrupted, .unwritable: .red } }
    private var sessionDataHealthDetail: String {
        switch model.sessionDataHealth {
        case .healthy: "本地会话数据正常"
        case let .corrupted(detail): detail
        case let .unwritable(detail): detail
        }
    }
}

private struct DestructiveConfirmation: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case deleteSession(id: String, title: String)
        case clearAll
    }
}
