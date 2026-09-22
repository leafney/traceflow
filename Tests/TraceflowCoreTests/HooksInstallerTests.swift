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
        XCTAssertEqual(commands.filter { $0 == installed.path }.count, 1)
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
        try? FileManager.default.removeItem(at: root)
    }
}
