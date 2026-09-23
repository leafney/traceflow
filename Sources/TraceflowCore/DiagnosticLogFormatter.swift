import Foundation

/// Safe, one-line diagnostic records shared by the hook forwarder and app.
public enum DiagnosticLogFormatter {
    public static func inputRejected(eventID: String, reason: String, bytes: Int) -> String {
        "stage=forwarder.input_rejected event_id=\(quoted(eventID)) reason=\(reason) bytes=\(max(0, bytes))"
    }

    public static func event(stage: String, envelope: HookEnvelope, receivedAt: Date? = nil, appliedAt: Date? = nil, extras: [(String, String)] = []) -> String {
        var fields = [
            "stage=\(stage)", "event_id=\(quoted(envelope.eventID))", "event=\(envelope.payload.eventName.rawValue)",
            "session_id=\(quoted(envelope.payload.sessionID))", "turn_id=\(quoted(envelope.payload.turnID ?? "none"))",
            "tool_name=\(quoted(envelope.payload.toolName ?? "none"))", "tool_use_id=\(quoted(envelope.payload.toolUseID ?? "none"))",
            "captured_uptime_ns=\(envelope.capturedUptimeNanoseconds)", "forwarded_at=\(quoted(iso8601(envelope.forwardedAt)))"
        ]
        if let receivedAt { fields.append("received_at=\(quoted(iso8601(receivedAt)))") }
        if let appliedAt { fields.append("applied_at=\(quoted(iso8601(appliedAt)))") }
        fields.append(contentsOf: extras.map { "\($0.0)=\(quoted($0.1))" })
        return fields.joined(separator: " ")
    }

    public static func socketDrop(reason: String, bytes: Int) -> String { "stage=app.socket_drop reason=\(reason) bytes=\(max(0, bytes))" }
    public static func decodeFailed(bytes: Int) -> String { "stage=app.decode_failed reason=invalid_envelope bytes=\(max(0, bytes))" }

    public static func quoted(_ value: String) -> String { "\"\(escape(truncate(value)))\"" }

    private static func truncate(_ value: String) -> String {
        let scalars = value.unicodeScalars
        guard scalars.count > 128 else { return value }
        return String(String.UnicodeScalarView(scalars.prefix(128))) + "…[truncated]"
    }

    private static func escape(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x5C: "\\\\"; case 0x22: "\\\""; case 0x0A: "\\n"; case 0x0D: "\\r"; case 0x09: "\\t"
            case 0x00...0x1F, 0x7F...0x9F: String(format: "\\u{%04X}", scalar.value)
            default: String(scalar)
            }
        }.joined()
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
