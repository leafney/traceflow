import Darwin
import XCTest
@testable import TraceflowCore

final class ProcessLifecycleTests: XCTestCase {
    func testTerminatesProcessThatIgnoresGracefulSignal() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)"]
        try process.run()
        let pid = process.processIdentifier

        XCTAssertTrue(ProcessLifecycle.terminate(process, gracefulTimeout: 0.1, forcedTimeout: 1))
        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(Darwin.kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testWaitForExitReturnsFalseAtDeadline() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["2"]
        try process.run()
        defer { ProcessLifecycle.terminate(process, gracefulTimeout: 0.1, forcedTimeout: 1) }

        XCTAssertFalse(ProcessLifecycle.waitForExit(process, timeout: 0.05))
    }
}
