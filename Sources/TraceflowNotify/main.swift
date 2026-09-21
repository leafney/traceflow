import Foundation
import TraceflowCore

private let maximumInputBytes = 1_048_576
let input = FileHandle.standardInput.readDataToEndOfFile()
guard !input.isEmpty, input.count <= maximumInputBytes,
      let payload = try? JSONDecoder().decode(HookPayload.self, from: input) else { exit(EXIT_SUCCESS) }

let envelope = HookEnvelope(
    eventID: UUID().uuidString,
    capturedUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
    forwardedAt: Date(),
    payload: payload
)
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
if let data = try? encoder.encode(envelope) {
    try? UnixSocketClient.send(data, to: TraceflowPaths.socket().path)
}
FileHandle.standardOutput.write(Data("{}\n".utf8))
