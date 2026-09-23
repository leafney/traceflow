import XCTest
import Darwin
@testable import TraceflowCore

final class UnixSocketTests: XCTestCase {
    private final class DataBox: @unchecked Sendable { var value = Data() }

    func testSendsOneMessageOverUnixSocket() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("test.sock").path
        let received = expectation(description: "received")
        let output = DataBox()
        let server = UnixSocketServer(path: path) { data in output.value = data; received.fulfill() }
        try server.start()
        try UnixSocketClient.send(Data("hello".utf8), to: path)
        wait(for: [received], timeout: 1)
        XCTAssertEqual(String(data: output.value, encoding: .utf8), "hello")
        server.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    func testRejectsOversizedMessage() {
        XCTAssertThrowsError(try UnixSocketClient.send(Data(count: 1_048_577), to: "/tmp/none"))
    }

    func testReportsEmptyClientPayload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("test.sock").path
        let dropped = expectation(description: "empty payload dropped")
        let server = UnixSocketServer(path: path, dropHandler: { drop in
            if drop == .emptyInput { dropped.fulfill() }
        }) { _ in XCTFail("empty input must not reach handler") }
        try server.start()
        let client = try connect(to: path)
        Darwin.shutdown(client, SHUT_WR)
        Darwin.close(client)
        wait(for: [dropped], timeout: 1)
        server.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    func testPartialClientTimesOutWithoutBlockingNextMessage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("test.sock").path
        let received = expectation(description: "received after stalled client")
        let output = DataBox()
        let server = UnixSocketServer(path: path) { data in output.value = data; received.fulfill() }
        try server.start()

        let stalled = try connect(to: path)
        XCTAssertEqual(Darwin.write(stalled, "half", 4), 4)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
            try? UnixSocketClient.send(Data("complete".utf8), to: path)
        }

        wait(for: [received], timeout: 3)
        XCTAssertEqual(String(data: output.value, encoding: .utf8), "complete")
        Darwin.close(stalled)
        server.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    private func connect(to path: String) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ECONNREFUSED) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0)
            for index in bytes.indices { raw[index] = UInt8(bitPattern: bytes[index]) }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { Darwin.close(fd); throw POSIXError(.ECONNREFUSED) }
        return fd
    }
}
