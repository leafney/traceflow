import XCTest
@testable import TraceflowCore

final class HooksInstallerTests: XCTestCase {
    func testInstallIsIdempotentPreservesOtherHooksAndRemoveIsPrecise() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let codex = root.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let hooks = codex.appendingPathComponent("hooks.json")
        try Data(#"{"description":"keep","hooks":{"Stop":[{"hooks":[{"type":"command","command":"other"}]}]}}"#.utf8).write(to: hooks)
        let source = root.appendingPathComponent("source-notify")
        try Data("binary".utf8).write(to: source); try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        let installed = root.appendingPathComponent("Library/Application Support/Traceflow/bin/traceflow-notify")
        let installer = HooksInstaller(hooksURL: hooks, installedNotifierURL: installed, sourceNotifierURL: source)
        try installer.installOrRepair(); try installer.installOrRepair()
        XCTAssertTrue(installer.isInstalled())
        let rootObject = try JSONSerialization.jsonObject(with: Data(contentsOf: hooks)) as! [String: Any]
        XCTAssertEqual(rootObject["description"] as? String, "keep")
        let groups = (rootObject["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        let commands = groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.compactMap { $0["command"] as? String }
        XCTAssertEqual(commands.filter { $0 == HooksInstaller.shellQuote(installed.path) }.count, 1)
        XCTAssertTrue(commands.contains("other"))
        try installer.remove()
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: hooks)) as! [String: Any]
        let afterGroups = (after["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        XCTAssertEqual(afterGroups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.compactMap { $0["command"] as? String }, ["other"])
        try? FileManager.default.removeItem(at: root)
    }

    func testInvalidJSONIsUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let hooks = root.appendingPathComponent("hooks.json"); try Data("bad".utf8).write(to: hooks)
        let source = root.appendingPathComponent("source"); try Data("x".utf8).write(to: source)
        let installer = HooksInstaller(hooksURL: hooks, installedNotifierURL: root.appendingPathComponent("installed"), sourceNotifierURL: source)
        XCTAssertThrowsError(try installer.installOrRepair())
        XCTAssertEqual(try String(contentsOf: hooks), "bad")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("installed").path))
        try? FileManager.default.removeItem(at: root)
    }

    func testRepairReplacesLegacyUnquotedCommandWithoutDuplicates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("Application Support/Traceflow/bin/traceflow-notify")
        let hooks = root.appendingPathComponent("hooks.json")
        let initial: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": destination.path], ["type": "command", "command": "other"]]]]]]
        try JSONSerialization.data(withJSONObject: initial).write(to: hooks)
        let source = root.appendingPathComponent("source"); try Data("binary".utf8).write(to: source)
        let installer = HooksInstaller(hooksURL: hooks, installedNotifierURL: destination, sourceNotifierURL: source)
        XCTAssertFalse(installer.isInstalled())
        try installer.installOrRepair()
        XCTAssertTrue(installer.isInstalled())
        let output = try JSONSerialization.jsonObject(with: Data(contentsOf: hooks)) as! [String: Any]
        let stop = ((output["hooks"] as! [String: Any])["Stop"] as! [[String: Any]])
        let commands = stop.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.compactMap { $0["command"] as? String }
        XCTAssertEqual(commands.filter { $0 == HooksInstaller.shellQuote(destination.path) }.count, 1)
        XCTAssertFalse(commands.contains(destination.path))
        XCTAssertTrue(commands.contains("other"))
        try? FileManager.default.removeItem(at: root)
    }

    func testQuotedCommandExecutesAtPathContainingSpaces() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = root.appendingPathComponent("Application Support/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let notifier = bin.appendingPathComponent("traceflow-notify")
        try Data("#!/bin/sh\nprintf 'ok\\n'\n".utf8).write(to: notifier)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notifier.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", HooksInstaller.shellQuote(notifier.path)]
        let output = Pipe(); process.standardOutput = output
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), "ok\n")
        try? FileManager.default.removeItem(at: root)
    }

    func testInspectionRejectsIncorrectTimeoutAndAsyncWithoutAffectingOtherHooks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let hooks = root.appendingPathComponent("hooks.json")
        let source = root.appendingPathComponent("source")
        let installed = root.appendingPathComponent("installed")
        try Data("binary".utf8).write(to: source)
        let installer = HooksInstaller(hooksURL: hooks, installedNotifierURL: installed, sourceNotifierURL: source)
        try installer.installOrRepair()

        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: hooks)) as! [String: Any]
        var allHooks = object["hooks"] as! [String: Any]
        var stopGroups = allHooks["Stop"] as! [[String: Any]]
        var handlers = stopGroups[0]["hooks"] as! [[String: Any]]
        handlers[0]["timeout"] = 9
        handlers[0]["async"] = true
        stopGroups[0]["hooks"] = handlers
        allHooks["Stop"] = stopGroups
        object["hooks"] = allHooks
        try JSONSerialization.data(withJSONObject: object).write(to: hooks)

        let inspection = installer.inspect()
        XCTAssertTrue(inspection.hasTraceflowConfiguration)
        XCTAssertFalse(inspection.isComplete)
        XCTAssertTrue(inspection.issues.contains { $0.contains("Stop") })
        XCTAssertFalse(installer.isInstalled())
        try? FileManager.default.removeItem(at: root)
    }

    func testInspectionRequiresSessionStartMatcherAndExecutableNotifier() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let hooks = root.appendingPathComponent("hooks.json")
        let source = root.appendingPathComponent("source")
        let installed = root.appendingPathComponent("installed")
        try Data("binary".utf8).write(to: source)
        let installer = HooksInstaller(hooksURL: hooks, installedNotifierURL: installed, sourceNotifierURL: source)
        try installer.installOrRepair()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: installed.path)

        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: hooks)) as! [String: Any]
        var allHooks = object["hooks"] as! [String: Any]
        var groups = allHooks["SessionStart"] as! [[String: Any]]
        groups[0]["matcher"] = "startup"
        allHooks["SessionStart"] = groups
        object["hooks"] = allHooks
        try JSONSerialization.data(withJSONObject: object).write(to: hooks)

        let inspection = installer.inspect()
        XCTAssertTrue(inspection.issues.contains { $0.contains("转发器") })
        XCTAssertTrue(inspection.issues.contains { $0.contains("SessionStart") })
        try? FileManager.default.removeItem(at: root)
    }
}
