import Foundation

/// Formats accepted Hook state transitions as one safe, searchable log line.
/// User-controlled values are always quoted and escaped so a single Hook event
/// cannot inject extra physical lines into Traceflow's text log.
public enum SessionEventLogFormatter {
    public static func stateTransition(
        event: HookEventName,
        oldState: SessionRuntimeState,
        newState: SessionRuntimeState,
        projectName: String,
        sessionID: String,
        title: String
    ) -> String {
        "event=\(event.rawValue) state=\(oldState.rawValue)->\(newState.rawValue) project=\(quoted(projectName)) session_id=\(quoted(sessionID)) title=\(quoted(title))"
    }

    private static func quoted(_ value: String) -> String {
        "\"\(escape(value))\""
    }

    private static func escape(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x5C: "\\\\"
            case 0x22: "\\\""
            case 0x0A: "\\n"
            case 0x0D: "\\r"
            case 0x09: "\\t"
            case 0x00...0x1F, 0x7F...0x9F:
                String(format: "\\u{%04X}", scalar.value)
            default:
                String(scalar)
            }
        }.joined()
    }
}
