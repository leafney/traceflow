import Darwin
import Foundation

public final class RotatingLogger: @unchecked Sendable {
    private let directory: URL
    private let maximumBytes: UInt64
    private let maximumFiles: Int
    private let queue = DispatchQueue(label: "io.traceflow.logger")

    public init(directory: URL, maximumBytes: UInt64 = 10 * 1_024 * 1_024, maximumFiles: Int = 5) {
        self.directory = directory
        self.maximumBytes = maximumBytes
        self.maximumFiles = max(1, maximumFiles)
    }

    public func log(_ message: String) { queue.async { [self] in append(message) } }
    public func logSynchronously(_ message: String) { queue.sync { append(message) } }
    public func flush() { queue.sync {} }

    public func clear() {
        queue.sync {
            withExclusiveLogLock {
                for index in 0..<maximumFiles {
                    let name = index == 0 ? "traceflow.log" : "traceflow.log.\(index)"
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                }
            }
        }
    }

    private func append(_ message: String) {
        let line = "\(Self.timestamp()) \(message)\n"
        guard let data = line.data(using: .utf8), UInt64(data.count) <= maximumBytes else { return }
        withExclusiveLogLock {
            rotateIfNeeded(incomingBytes: UInt64(data.count))
            let active = directory.appendingPathComponent("traceflow.log")
            if !FileManager.default.fileExists(atPath: active.path) {
                FileManager.default.createFile(atPath: active.path, contents: nil, attributes: [.posixPermissions: 0o600])
                chmod(active.path, 0o600)
            }
            guard let handle = try? FileHandle(forWritingTo: active) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private func withExclusiveLogLock(_ body: () -> Void) {
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil else { return }
        let lockURL = directory.appendingPathComponent("traceflow.log.lock")
        let fd = Darwin.open(lockURL.path, O_CREAT | O_RDWR, mode_t(0o600))
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        chmod(lockURL.path, 0o600)
        guard flock(fd, LOCK_EX) == 0 else { return }
        defer { flock(fd, LOCK_UN) }
        body()
    }

    private func rotateIfNeeded(incomingBytes: UInt64) {
        let active = directory.appendingPathComponent("traceflow.log")
        let size = ((try? FileManager.default.attributesOfItem(atPath: active.path)[.size]) as? NSNumber)?.uint64Value ?? 0
        guard size > 0, size + incomingBytes > maximumBytes else { return }
        if maximumFiles > 1 {
            for index in stride(from: maximumFiles - 1, through: 1, by: -1) {
                let destination = directory.appendingPathComponent("traceflow.log.\(index)")
                try? FileManager.default.removeItem(at: destination)
                let source = directory.appendingPathComponent(index == 1 ? "traceflow.log" : "traceflow.log.\(index - 1)")
                if FileManager.default.fileExists(atPath: source.path) { try? FileManager.default.moveItem(at: source, to: destination) }
            }
        } else { try? FileManager.default.removeItem(at: active) }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
