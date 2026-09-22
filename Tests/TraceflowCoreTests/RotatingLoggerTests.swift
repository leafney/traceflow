import XCTest
@testable import TraceflowCore

final class RotatingLoggerTests: XCTestCase {
    func testRotatesBySizeAndKeepsMaximumFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = RotatingLogger(directory: directory, maximumBytes: 80, maximumFiles: 3)
        for index in 0..<20 { logger.log("event=Stop session=abc state=\(index)") }
        logger.flush()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("traceflow.log") }
        XCTAssertLessThanOrEqual(files.count, 3)
        XCTAssertGreaterThan(files.count, 1)
        let unrelated = directory.appendingPathComponent("keep.txt")
        try Data("保留".utf8).write(to: unrelated)
        logger.clear()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["keep.txt"])
        try? FileManager.default.removeItem(at: directory)
    }
}
