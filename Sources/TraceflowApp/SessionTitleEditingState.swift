import Combine
import TraceflowCore

/// Owns one edit transaction. Model updates never replace its local draft.
@MainActor
final class SessionTitleEditingState: ObservableObject {
    let model: AppModel
    let sessionID: String
    @Published var draft: String { didSet { saveError = nil } }
    @Published private(set) var saveError: String?

    init(model: AppModel, session: SessionSnapshot) {
        self.model = model
        sessionID = session.id
        draft = session.effectiveConversationTitle ?? ""
    }

    var session: SessionSnapshot? { model.sessions.first { $0.id == sessionID } }
    var unavailableMessage: String? {
        if session == nil { return "会话已不存在" }
        if !model.sessionDataHealth.allowsSaving { return "会话数据暂时无法保存，请先修复" }
        return nil
    }
    var validationMessage: String? {
        do { _ = try SessionTitleEditor.normalizedTitle(draft); return nil }
        catch { return error.localizedDescription }
    }
    var message: String? {
        // A missing target takes precedence over a historical write failure.
        if session == nil { return "会话已不存在" }
        return saveError ?? unavailableMessage ?? validationMessage
    }
    var canSave: Bool { unavailableMessage == nil && validationMessage == nil }
    var canRestore: Bool { unavailableMessage == nil && session?.persisted.customTitle != nil }

    /// True means the view may dismiss. Invalid input and write errors keep it open.
    func save() -> Bool {
        guard canSave else { return false }
        do { try model.setCustomTitle(draft, sessionID: sessionID); return true }
        catch { saveError = error.localizedDescription; return false }
    }

    func restore() -> Bool {
        guard canRestore else { return false }
        do { try model.resetCustomTitle(sessionID: sessionID); return true }
        catch { saveError = error.localizedDescription; return false }
    }
}
