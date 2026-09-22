import Foundation

public enum HooksInstallerError: LocalizedError {
    case invalidJSON
    case missingNotifier
    public var errorDescription: String? {
        switch self { case .invalidJSON: "现有 hooks.json 不是有效 JSON，未做修改"; case .missingNotifier: "找不到可安装的 traceflow-notify" }
    }
}

public struct HooksInstaller {
    public let hooksURL: URL
    public let installedNotifierURL: URL
    public let sourceNotifierURL: URL
    public init(hooksURL: URL, installedNotifierURL: URL, sourceNotifierURL: URL) { self.hooksURL = hooksURL; self.installedNotifierURL = installedNotifierURL; self.sourceNotifierURL = sourceNotifierURL }

    public func installOrRepair() throws {
        guard FileManager.default.fileExists(atPath: sourceNotifierURL.path) else { throw HooksInstallerError.missingNotifier }
        try FileManager.default.createDirectory(at: installedNotifierURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: installedNotifierURL.path) { try FileManager.default.removeItem(at: installedNotifierURL) }
        try FileManager.default.copyItem(at: sourceNotifierURL, to: installedNotifierURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedNotifierURL.path)
        var root = try readRoot()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in Self.events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups = removingTraceflowHandlers(from: groups)
            var handler: [String: Any] = ["type": "command", "command": installedNotifierURL.path, "timeout": 3]
            if !["Stop", "SessionEnd"].contains(event) { handler["async"] = true }
            var group: [String: Any] = ["hooks": [handler]]
            if event == "SessionStart" { group["matcher"] = "startup|resume|clear" }
            groups.append(group)
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try backupAndWrite(root)
    }

    public func remove() throws {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else { return }
        var root = try readRoot()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for key in Array(hooks.keys) {
            let groups = removingTraceflowHandlers(from: hooks[key] as? [[String: Any]] ?? [])
            if groups.isEmpty { hooks.removeValue(forKey: key) } else { hooks[key] = groups }
        }
        root["hooks"] = hooks
        try backupAndWrite(root)
        try? FileManager.default.removeItem(at: installedNotifierURL)
    }

    public func isInstalled() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: installedNotifierURL.path), let root = try? readRoot(), let hooks = root["hooks"] as? [String: Any] else { return false }
        return Self.events.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String) == installedNotifierURL.path }
            }
        }
    }

    private func readRoot() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else { return [:] }
        let data = try Data(contentsOf: hooksURL)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HooksInstallerError.invalidJSON }
        return root
    }

    private func removingTraceflowHandlers(from groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group in
            var copy = group
            let filtered = (group["hooks"] as? [[String: Any]] ?? []).filter { ($0["command"] as? String) != installedNotifierURL.path }
            guard !filtered.isEmpty else { return nil }
            copy["hooks"] = filtered
            return copy
        }
    }

    private func backupAndWrite(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(at: hooksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: hooksURL.path) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try FileManager.default.copyItem(at: hooksURL, to: hooksURL.deletingLastPathComponent().appendingPathComponent("hooks.json.backup-\(stamp)-\(UUID().uuidString.prefix(8))"))
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        _ = try JSONSerialization.jsonObject(with: data)
        let temp = hooksURL.deletingLastPathComponent().appendingPathComponent(".hooks-\(UUID().uuidString).tmp")
        try data.write(to: temp, options: .atomic)
        if FileManager.default.fileExists(atPath: hooksURL.path) { _ = try FileManager.default.replaceItemAt(hooksURL, withItemAt: temp) }
        else { try FileManager.default.moveItem(at: temp, to: hooksURL) }
    }

    public static let events = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop", "Interrupt", "SessionEnd"]
}
