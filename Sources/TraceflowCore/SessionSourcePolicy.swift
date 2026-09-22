import Foundation

public enum SessionSourcePolicy {
    public static let allowedAppServerKinds = ["cli", "vscode", "appServer"]

    public static func isAllowedAppServerKind(_ source: String?) -> Bool {
        guard let source else { return true }
        return allowedAppServerKinds.contains(source)
    }

    public static func isInternalHookSource(_ source: String?) -> Bool {
        guard let source else { return false }
        return source == "exec" || source == "unknown" || source.hasPrefix("subAgent")
    }
}
