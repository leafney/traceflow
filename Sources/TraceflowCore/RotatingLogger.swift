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

    public func log(_ message: String) {
        queue.async { [self] in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            rotateIfNeeded(incomingBytes: UInt64(message.utf8.count + 1))
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
            let url = directory.appendingPathComponent("traceflow.log")
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    public func flush() { queue.sync {} }

    public func clear() {
        queue.sync {
            for index in 0..<maximumFiles {
                let name = index == 0 ? "traceflow.log" : "traceflow.log.\(index)"
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    private func rotateIfNeeded(incomingBytes: UInt64) {
        let active = directory.appendingPathComponent("traceflow.log")
        let size = ((try? FileManager.default.attributesOfItem(atPath: active.path)[.size]) as? NSNumber)?.uint64Value ?? 0
        guard size + incomingBytes > maximumBytes else { return }
        if maximumFiles > 1 {
            for index in stride(from: maximumFiles - 1, through: 1, by: -1) {
                let destination = directory.appendingPathComponent("traceflow.log.\(index)")
                try? FileManager.default.removeItem(at: destination)
                let sourceName = index == 1 ? "traceflow.log" : "traceflow.log.\(index - 1)"
                let source = directory.appendingPathComponent(sourceName)
                if FileManager.default.fileExists(atPath: source.path) { try? FileManager.default.moveItem(at: source, to: destination) }
            }
        } else { try? FileManager.default.removeItem(at: active) }
    }
}
