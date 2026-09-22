import Darwin
import Foundation

public enum ProcessLifecycle {
    public static func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: max(0, timeout))
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        return !process.isRunning
    }

    @discardableResult
    public static func terminate(
        _ process: Process,
        gracefulTimeout: TimeInterval = 1,
        forcedTimeout: TimeInterval = 1
    ) -> Bool {
        guard process.isRunning else { return true }
        process.terminate()
        if waitForExit(process, timeout: gracefulTimeout) { return true }
        Darwin.kill(process.processIdentifier, SIGKILL)
        return waitForExit(process, timeout: forcedTimeout)
    }
}
