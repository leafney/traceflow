import Foundation

public enum TraceflowPaths {
    public static func applicationSupport(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Traceflow", isDirectory: true)
    }

    public static func socket(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        applicationSupport(home: home).appendingPathComponent("traceflow.sock")
    }

    public static func sessions(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        applicationSupport(home: home).appendingPathComponent("sessions.json")
    }

    public static func installedNotifier(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        applicationSupport(home: home).appendingPathComponent("bin/traceflow-notify")
    }

    public static func logs(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Logs/Traceflow", isDirectory: true)
    }
}
