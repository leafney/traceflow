import Foundation
import TraceflowCore

private let maximumInputBytes = 1_048_576
private let logger = RotatingLogger(directory: TraceflowPaths.logs())
private let eventID = UUID().uuidString
private let input = FileHandle.standardInput.readDataToEndOfFile()

func finish() -> Never {
    logger.flush()
    FileHandle.standardOutput.write(Data("{}\n".utf8))
    exit(EXIT_SUCCESS)
}

guard !input.isEmpty else {
    logger.logSynchronously(DiagnosticLogFormatter.inputRejected(eventID: eventID, reason: "empty_input", bytes: input.count))
    finish()
}
guard input.count <= maximumInputBytes else {
    logger.logSynchronously(DiagnosticLogFormatter.inputRejected(eventID: eventID, reason: "oversize_input", bytes: input.count))
    finish()
}
guard (try? JSONSerialization.jsonObject(with: input)) != nil else {
    logger.logSynchronously(DiagnosticLogFormatter.inputRejected(eventID: eventID, reason: "invalid_json", bytes: input.count))
    finish()
}
guard let payload = try? JSONDecoder().decode(HookPayload.self, from: input) else {
    logger.logSynchronously(DiagnosticLogFormatter.inputRejected(eventID: eventID, reason: "invalid_payload", bytes: input.count))
    finish()
}

let envelope = HookEnvelope(eventID: eventID, capturedUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds, forwardedAt: Date(), payload: payload)
logger.logSynchronously(DiagnosticLogFormatter.event(stage: "forwarder.received", envelope: envelope))

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
do {
    let data = try encoder.encode(envelope)
    try UnixSocketClient.send(data, to: TraceflowPaths.socket().path)
    logger.logSynchronously(DiagnosticLogFormatter.event(stage: "forwarder.sent", envelope: envelope, extras: [("result", "write_completed")]))
} catch {
    logger.logSynchronously(DiagnosticLogFormatter.event(stage: "forwarder.send_failed", envelope: envelope, extras: safeErrorFields(error)))
}
finish()

private func safeErrorFields(_ error: Error) -> [(String, String)] {
    guard let socketError = error as? UnixSocketError else { return [("operation", "unknown")] }
    switch socketError {
    case .pathTooLong: return [("operation", "path_too_long")]
    case .messageTooLarge: return [("operation", "message_too_large")]
    case let .systemCall(operation, code): return [("operation", operation), ("errno", String(code))]
    }
}
