import SwiftUI
import TraceflowCore

struct SessionTitleEditorView: View {
    @ObservedObject var model: AppModel
    @StateObject private var editing: SessionTitleEditingState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    init(model: AppModel, session: SessionSnapshot) {
        self.model = model
        _editing = StateObject(wrappedValue: SessionTitleEditingState(model: model, session: session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑会话标题").font(.headline)
            Text("\(editing.session?.persisted.projectName ?? "未知项目") · \(String(editing.sessionID.prefix(8)))")
                .font(.caption).foregroundStyle(.secondary)
            TextField("会话标题", text: $editing.draft)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .accessibilityLabel("会话标题")
                .onSubmit { save() }
            HStack {
                Text("仅修改本地显示标题，项目名保持不变").foregroundStyle(.secondary)
                Spacer()
                Text("\(editing.draft.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(SessionTitleEditor.maximumLength)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }.font(.caption)
            if let message = editing.message {
                Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("恢复默认标题") { restore() }
                    .disabled(!editing.canRestore)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(!editing.canSave)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(.background)
        .onAppear { titleFocused = true }
    }

    private func save() {
        if editing.save() { dismiss() }
    }

    private func restore() {
        if editing.restore() { dismiss() }
    }
}
