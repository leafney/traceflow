import Foundation

public enum TraceflowPaths {
    public static var defaultHome: URL {
        if let override = ProcessInfo.processInfo.environment["TRACEFLOW_HOME"], !override.isEmpty { return URL(fileURLWithPath: override, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static func applicationSupport(home: URL = defaultHome) -> URL {
        home.appendingPathComponent("Library/Application Support/Traceflow", isDirectory: true)
    }

    public static func socket(home: URL = defaultHome) -> URL {
        applicationSupport(home: home).appendingPathComponent("traceflow.sock")
    }

    public static func sessions(home: URL = defaultHome) -> URL {
        applicationSupport(home: home).appendingPathComponent("sessions.json")
    }

    public static func installedNotifier(home: URL = defaultHome) -> URL {
        applicationSupport(home: home).appendingPathComponent("bin/traceflow-notify")
    }

    public static func logs(home: URL = defaultHome) -> URL {
        home.appendingPathComponent("Library/Logs/Traceflow", isDirectory: true)
    }
}
