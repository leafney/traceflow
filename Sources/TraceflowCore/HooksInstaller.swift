import Foundation

public enum HooksInstallerError: LocalizedError {
    case invalidJSON
    case missingNotifier
    public var errorDescription: String? {
        switch self { case .invalidJSON: "现有 hooks.json 不是有效 JSON，未做修改"; case .missingNotifier: "找不到可安装的 traceflow-notify" }
    }
}

public enum HooksConfigurationState: Sendable, Equatable {
    case missing
    case corrupted
    case incomplete
    case complete
}

public struct HooksInspection: Sendable, Equatable {
    public let state: HooksConfigurationState
    public let issues: [String]
    public var hasTraceflowConfiguration: Bool { state == .incomplete || state == .complete }
    public var isComplete: Bool { state == .complete }
    public var summary: String { issues.first ?? "配置完整" }
}

public struct HooksInstaller {
    public let hooksURL: URL
    public let installedNotifierURL: URL
    public let sourceNotifierURL: URL
    public init(hooksURL: URL, installedNotifierURL: URL, sourceNotifierURL: URL) { self.hooksURL = hooksURL; self.installedNotifierURL = installedNotifierURL; self.sourceNotifierURL = sourceNotifierURL }

    public func installOrRepair() throws {
        guard FileManager.default.fileExists(atPath: sourceNotifierURL.path) else { throw HooksInstallerError.missingNotifier }
        var root = try readRoot()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in Self.events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups = removingTraceflowHandlers(from: groups)
            // Every state-bearing lifecycle event is synchronous. An async
            // PermissionRequest can arrive after a later PreToolUse and falsely
            // put an already-working session back into attention/red.
            let handler: [String: Any] = ["type": "command", "command": Self.shellQuote(installedNotifierURL.path), "timeout": 3]
            var group: [String: Any] = ["hooks": [handler]]
            if event == "SessionStart" { group["matcher"] = "startup|resume|clear" }
            groups.append(group)
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try FileManager.default.createDirectory(at: installedNotifierURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staged = installedNotifierURL.deletingLastPathComponent().appendingPathComponent(".traceflow-notify-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: sourceNotifierURL, to: staged)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
        if FileManager.default.fileExists(atPath: installedNotifierURL.path) {
            _ = try FileManager.default.replaceItemAt(installedNotifierURL, withItemAt: staged)
        } else {
            try FileManager.default.moveItem(at: staged, to: installedNotifierURL)
        }
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
        inspect().isComplete
    }

    public func inspect() -> HooksInspection {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            let state: HooksConfigurationState = FileManager.default.fileExists(atPath: installedNotifierURL.path) ? .incomplete : .missing
            return HooksInspection(state: state, issues: state == .missing ? ["尚未安装 Traceflow Hooks"] : ["Hooks 配置缺失"])
        }
        let root: [String: Any]
        do {
            root = try readRoot()
        } catch {
            return HooksInspection(state: .corrupted, issues: ["hooks.json 已损坏或无法读取"])
        }
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let expectedCommand = Self.shellQuote(installedNotifierURL.path)
        let hasConfiguration = hooks.values.contains { value in
            (value as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { handler in
                    isTraceflowCommand(handler["command"] as? String)
                }
            }
        }
        var issues: [String] = []
        if !FileManager.default.isExecutableFile(atPath: installedNotifierURL.path) {
            issues.append("Traceflow 转发器缺失或不可执行")
        }
        for event in Self.events {
            let groups = hooks[event] as? [[String: Any]] ?? []
            let matchingGroup = groups.first { group in
                guard event != "SessionStart" || (group["matcher"] as? String) == "startup|resume|clear" else { return false }
                return (group["hooks"] as? [[String: Any]] ?? []).contains { handler in
                    guard (handler["type"] as? String) == "command",
                          (handler["command"] as? String) == expectedCommand,
                          number(handler["timeout"]) == 3 else { return false }
                    return (handler["async"] as? Bool) != true
                }
            }
            if matchingGroup == nil { issues.append("\(event) 定义缺失或不完整") }
        }
        if !hasConfiguration {
            return HooksInspection(state: FileManager.default.fileExists(atPath: installedNotifierURL.path) ? .incomplete : .missing, issues: ["Traceflow Hooks 定义缺失"])
        }
        return HooksInspection(state: issues.isEmpty ? .complete : .incomplete, issues: issues)
    }

    private func number(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
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
            let filtered = (group["hooks"] as? [[String: Any]] ?? []).filter { !isTraceflowCommand($0["command"] as? String) }
            guard !filtered.isEmpty else { return nil }
            copy["hooks"] = filtered
            return copy
        }
    }

    private func isTraceflowCommand(_ command: String?) -> Bool {
        command == installedNotifierURL.path || command == Self.shellQuote(installedNotifierURL.path)
    }

    public static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
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

    public static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop", "Interrupt", "SessionEnd"]
}
