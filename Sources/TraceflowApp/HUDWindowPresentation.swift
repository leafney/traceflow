import Combine
import TraceflowCore

enum HUDWindowDisplayMode: Equatable {
    case placeholder
    case session

    init(session: SessionSnapshot?) {
        self = session == nil ? .placeholder : .session
    }
}

enum HUDPanelPlacement {
    case restoreLayoutPosition
    case preserveCurrentGeometry
}

/// A window never crosses the placeholder/session boundary in its own surface.
/// Live previews retain the ordinary model-driven behavior without a subscription.
@MainActor
final class HUDWindowPresentation: ObservableObject {
    private weak var model: AppModel?
    private let mode: HUDWindowDisplayMode?
    @Published private var lastSession: SessionSnapshot?
    private var sessionObserver: AnyCancellable?

    var displayedSession: SessionSnapshot? {
        guard let mode else { return model?.displayedSession }
        return mode == .placeholder ? nil : lastSession
    }

    init(model: AppModel, mode: HUDWindowDisplayMode? = nil) {
        self.model = model
        self.mode = mode
        lastSession = mode == .session ? model.displayedSession : nil
        if mode == .session {
            sessionObserver = model.$displayedSession.dropFirst().sink { [weak self] session in
                // Published emits before the model commits. Use this snapshot,
                // synchronously, so A -> B -> nil retains B until retirement.
                guard let session else { return }
                self?.lastSession = session
            }
        }
    }
}
