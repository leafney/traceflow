import XCTest
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
}
