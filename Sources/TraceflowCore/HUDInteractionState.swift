public struct HUDInteractionState {
    public private(set) var isPinned: Bool
    public private(set) var isDragging = false

    public var ignoresMouseEvents: Bool { isPinned }
    public var canBeginDrag: Bool { !isPinned }

    public init(isPinned: Bool) {
        self.isPinned = isPinned
    }

    public mutating func cancelDrag() {
        isDragging = false
    }

    @discardableResult
    public mutating func beginDrag() -> Bool {
        guard canBeginDrag else { return false }
        isDragging = true
        return true
    }

    @discardableResult
    public mutating func finishDrag() -> Bool {
        guard isDragging, !isPinned else { return false }
        isDragging = false
        return true
    }

    @discardableResult
    public mutating func setPinned(_ pinned: Bool) -> Bool {
        let shouldCancelDrag = pinned && isDragging
        isPinned = pinned
        if shouldCancelDrag { isDragging = false }
        return shouldCancelDrag
    }
}
