import AppKit
import Combine
import TraceflowCore

@MainActor
final class SessionColorPanelTarget: NSObject {
    let changed: (NSColorPanel) -> Void
    init(changed: @escaping (NSColorPanel) -> Void) { self.changed = changed }
    @objc func colorChanged(_ sender: NSColorPanel) { changed(sender) }
}

/// One system panel, bound to a session ID rather than a mutable list position or carousel selection.
@MainActor
final class SessionColorPanelController {
    private weak var model: AppModel?
    private(set) var target: SessionColorPanelTarget?
    private var generation = 0
    private(set) var sessionID: String?
    private var sessionsObserver: AnyCancellable?
    private var healthObserver: AnyCancellable?
    private var closeObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        sessionsObserver = model.$sessions.sink { [weak self] sessions in
            guard let self, let id = self.sessionID else { return }
            if !sessions.contains(where: { $0.id == id }) { self.close() }
        }
        healthObserver = model.$sessionDataHealth.sink { [weak self] health in
            if !health.allowsSaving { self?.close() }
        }
    }

    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }

    func open(sessionID id: String) {
        guard let model, model.sessionDataHealth.allowsSaving,
              let session = model.sessions.first(where: { $0.id == id }) else { return }
        let panel = NSColorPanel.shared
        close()
        model.markerColorErrorMessage = nil
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = SessionMarkerView.nsColor(session.persisted.markerColorHex)
        generation += 1
        let token = generation
        sessionID = id
        target = SessionColorPanelTarget { [weak self] sender in
            self?.save(sender.color, sessionID: id, generation: token)
        }
        panel.setTarget(target)
        panel.setAction(#selector(SessionColorPanelTarget.colorChanged(_:)))
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                               object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.endBinding() }
        }
        panel.orderFront(nil)
    }

    private func save(_ color: NSColor, sessionID id: String, generation token: Int) {
        guard token == generation, sessionID == id, let model else { return }
        guard let rgb = color.usingColorSpace(.sRGB) else {
            close()
            model.markerColorErrorMessage = "无法转换所选颜色，未更改会话颜色"
            return
        }
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
            .map { Int((min(1, max(0, $0)) * 255).rounded()) }
        let hex = String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
        do { try model.setMarkerColor(hex, sessionID: id) }
        catch {
            close()
            model.markerColorErrorMessage = "颜色保存失败，未更改会话颜色"
        }
    }

    private func endBinding() {
        generation += 1
        sessionID = nil
        target = nil
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
    }

    func close() {
        guard sessionID != nil else { return }
        endBinding()
        NSColorPanel.shared.orderOut(nil)
    }
}
