import SwiftUI
import TraceflowCore

struct SessionTitleEditorView: View {
    @ObservedObject var model: AppModel
    let sessionID: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var saveError: String?
    @FocusState private var titleFocused: Bool

    init(model: AppModel, session: SessionSnapshot) {
        self.model = model
        sessionID = session.id
        _draft = State(initialValue: session.effectiveConversationTitle ?? "")
    }

    private var session: SessionSnapshot? { model.sessions.first { $0.id == sessionID } }
    private var unavailableMessage: String? {
        if session == nil { return "会话已不存在" }
        if !model.sessionDataHealth.allowsSaving { return "会话数据暂时无法保存，请先修复" }
        return nil
    }
    private var validationMessage: String? {
        do { _ = try SessionTitleEditor.normalizedTitle(draft); return nil }
        catch { return error.localizedDescription }
    }
    private var canSave: Bool { unavailableMessage == nil && validationMessage == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑会话标题").font(.headline)
            Text("\(session?.persisted.projectName ?? "未知项目") · \(String(sessionID.prefix(8)))")
                .font(.caption).foregroundStyle(.secondary)
            TextField("会话标题", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .accessibilityLabel("会话标题")
                .onSubmit { save() }
            HStack {
                Text("仅修改本地显示标题，项目名保持不变").foregroundStyle(.secondary)
                Spacer()
                Text("\(draft.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(SessionTitleEditor.maximumLength)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }.font(.caption)
            if let message = saveError ?? unavailableMessage ?? validationMessage {
                Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("恢复默认标题") { restore() }
                    .disabled(unavailableMessage != nil || session?.persisted.customTitle == nil)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { titleFocused = true }
        .onChange(of: draft) { saveError = nil }
    }

    private func save() {
        guard canSave else { return }
        do { try model.setCustomTitle(draft, sessionID: sessionID); dismiss() }
        catch { saveError = error.localizedDescription }
    }

    private func restore() {
        guard unavailableMessage == nil else { return }
        do { try model.resetCustomTitle(sessionID: sessionID); dismiss() }
        catch { saveError = error.localizedDescription }
    }
}
