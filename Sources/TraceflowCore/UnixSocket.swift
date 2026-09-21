import Darwin
import Foundation

public enum UnixSocketError: Error, Equatable {
    case pathTooLong
    case systemCall(String, Int32)
    case messageTooLarge
}

public enum UnixSocketClient {
    public static func send(_ data: Data, to path: String, timeoutMilliseconds: Int32 = 200) throws {
        guard data.count <= 1_048_576 else { throw UnixSocketError.messageTooLarge }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw failure("socket") }
        defer { Darwin.close(fd) }
        var timeout = timeval(tv_sec: 0, tv_usec: timeoutMilliseconds * 1_000)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var address = try makeAddress(path)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw failure("connect") }
        try data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                guard count > 0 else { throw failure("write") }
                sent += count
            }
        }
        Darwin.shutdown(fd, SHUT_WR)
    }
}

public final class UnixSocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (Data) -> Void
    private let path: String
    private let handler: Handler
    private let queue: DispatchQueue
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?

    public init(path: String, queue: DispatchQueue = DispatchQueue(label: "io.traceflow.socket"), handler: @escaping Handler) {
        self.path = path
        self.queue = queue
        self.handler = handler
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        unlink(path)
        fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw failure("socket") }
        var address = try makeAddress(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { stop(); throw failure("bind") }
        chmod(path, 0o600)
        guard Darwin.listen(fd, 16) == 0 else { stop(); throw failure("listen") }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptAvailable() }
        source.setCancelHandler { [fd] in if fd >= 0 { Darwin.close(fd) } }
        self.source = source
        source.resume()
    }

    public func stop() {
        if let source { source.cancel() }
        else if fd >= 0 { Darwin.close(fd) }
        source = nil
        fd = -1
        unlink(path)
    }

    deinit { stop() }

    private func acceptAvailable() {
        let client = Darwin.accept(fd, nil, nil)
        guard client >= 0 else { return }
        defer { Darwin.close(client) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(client, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
            if data.count > 1_048_576 { return }
        }
        if !data.isEmpty { handler(data) }
    }
}

private func makeAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = path.utf8CString
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw UnixSocketError.pathTooLong }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        raw.initializeMemory(as: UInt8.self, repeating: 0)
        for index in bytes.indices { raw[index] = UInt8(bitPattern: bytes[index]) }
    }
    return address
}

private func failure(_ operation: String) -> UnixSocketError {
    UnixSocketError.systemCall(operation, errno)
}
