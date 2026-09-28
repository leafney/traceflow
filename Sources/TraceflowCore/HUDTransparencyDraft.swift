/// A preview may change freely; continuous mouse editing commits only on release.
public struct HUDTransparencyDraft {
    public private(set) var value: Int
    public private(set) var isEditing = false
    public private(set) var isDirty = false

    public init(_ value: Int) { self.value = HUDBackgroundAppearance.normalize(Double(value)) }

    public mutating func preview(_ value: Double) {
        self.value = HUDBackgroundAppearance.normalize(value)
        isDirty = true
    }

    public mutating func setEditing(_ editing: Bool) { isEditing = editing }

    public mutating func takeCommit() -> Int? {
        guard isDirty else { return nil }
        isDirty = false
        return value
    }
}
