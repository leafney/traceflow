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

    public static func carouselSwitch(
        fromSessionID: String?,
        toSessionID: String?,
        projectName: String?,
        state: SessionRuntimeState?,
        reason: CarouselSwitchReason,
        cycle: PresentationCycle?
    ) -> String {
        let mode = cycle?.timingModeSnapshot.rawValue ?? "none"
        let duration = cycle.map { String($0.durationSnapshot) } ?? "none"
        return "carousel=switch from_session_id=\(quoted(fromSessionID ?? "none")) to_session_id=\(quoted(toSessionID ?? "none")) to_project=\(quoted(projectName ?? "none")) to_state=\(state?.rawValue ?? "none") reason=\(String(describing: reason)) timing_mode=\(mode) duration_seconds=\(duration)"
    }

    public static func carouselSettings(mode: CarouselTimingMode, uniformDuration: TimeInterval) -> String {
        "carousel=settings_changed timing_mode=\(mode.rawValue) uniform_duration_seconds=\(uniformDuration) applies=next_cycle"
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
