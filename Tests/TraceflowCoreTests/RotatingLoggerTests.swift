import XCTest
@testable import TraceflowCore

final class RotatingLoggerTests: XCTestCase {
    func testRotatesBySizeAndKeepsMaximumFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = RotatingLogger(directory: directory, maximumBytes: 80, maximumFiles: 3)
        for index in 0..<20 { logger.log("event=Stop session=abc state=\(index)") }
        logger.flush()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter {
            $0 == "traceflow.log" || ($0.hasPrefix("traceflow.log.") && $0.dropFirst("traceflow.log.".count).allSatisfy(\.isNumber))
        }
        XCTAssertLessThanOrEqual(files.count, 3)
        XCTAssertGreaterThan(files.count, 1)
        let unrelated = directory.appendingPathComponent("keep.txt")
        try Data("保留".utf8).write(to: unrelated)
        logger.clear()
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(remaining, ["keep.txt", "traceflow.log.lock"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("traceflow.log.lock").path))
        try? FileManager.default.removeItem(at: directory)
    }

    func testConcurrentProcessesKeepCompleteLines() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let executable = projectRoot.appendingPathComponent(".build/debug/traceflow-notify")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
        let first = try launchNotifier(at: executable, home: directory, sessionID: "first")
        let second = try launchNotifier(at: executable, home: directory, sessionID: "second")
        first.waitUntilExit()
        second.waitUntilExit()
        XCTAssertEqual(first.terminationStatus, 0)
        XCTAssertEqual(second.terminationStatus, 0)
        let logURL = directory.appendingPathComponent("Library/Logs/Traceflow/traceflow.log")
        let lines = try String(contentsOf: logURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(lines.filter { $0.contains("session_id=\"first\"") }.count, 2)
        XCTAssertEqual(lines.filter { $0.contains("session_id=\"second\"") }.count, 2)
        XCTAssertTrue(lines.allSatisfy { $0.contains(" stage=") })
        try? FileManager.default.removeItem(at: directory)
    }

    private func launchNotifier(at executable: URL, home: URL, sessionID: String) throws -> Process {
        let process = Process()
        process.executableURL = executable
        var environment = ProcessInfo.processInfo.environment
        environment["TRACEFLOW_HOME"] = home.path
        process.environment = environment
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let json = "{\"session_id\":\"\(sessionID)\",\"hook_event_name\":\"PreToolUse\"}"
        try input.fileHandleForWriting.write(contentsOf: Data(json.utf8))
        try input.fileHandleForWriting.close()
        return process
    }
}
