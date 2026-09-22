import Foundation
import Darwin

public struct CodexThreadSummary: Codable, Sendable, Equatable {
    public let id: String
    public let name: String?
    public let cwd: String
    public let createdAt: Date
    public let updatedAt: Date
    public let sourceKind: String?

    public init(id: String, name: String?, cwd: String, createdAt: Date, updatedAt: Date, sourceKind: String? = nil) {
        self.id = id
        self.name = name
        self.cwd = cwd
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceKind = sourceKind
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, cwd, createdAt, updatedAt, sourceKind, source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        cwd = try container.decode(String.self, forKey: .cwd)
        createdAt = Date(timeIntervalSince1970: TimeInterval(try container.decode(Int64.self, forKey: .createdAt)))
        updatedAt = Date(timeIntervalSince1970: TimeInterval(try container.decode(Int64.self, forKey: .updatedAt)))
        sourceKind = try container.decodeIfPresent(String.self, forKey: .sourceKind)
            ?? container.decodeIfPresent(String.self, forKey: .source)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(Int64(createdAt.timeIntervalSince1970), forKey: .createdAt)
        try container.encode(Int64(updatedAt.timeIntervalSince1970), forKey: .updatedAt)
        try container.encodeIfPresent(sourceKind, forKey: .sourceKind)
    }
}

public struct CodexThreadListPage: Sendable, Equatable {
    public let threads: [CodexThreadSummary]
    public let nextCursor: String?

    public init(threads: [CodexThreadSummary], nextCursor: String?) {
        self.threads = threads
        self.nextCursor = nextCursor
    }

    public static func decode(from result: Any) throws -> CodexThreadListPage {
        guard JSONSerialization.isValidJSONObject(result) else {
            throw CodexAppServerError.invalidResponse
        }
        let data = try JSONSerialization.data(withJSONObject: result)
        let response = try JSONDecoder().decode(Response.self, from: data)
        return CodexThreadListPage(threads: response.data, nextCursor: response.nextCursor)
    }

    private struct Response: Decodable {
        let data: [CodexThreadSummary]
        let nextCursor: String?
    }
}

public struct CodexThreadImportResult: Sendable, Equatable {
    public let sessions: [PersistedSession]
    public let addedCount: Int
    public let updatedCount: Int
    public let nextRotationIndex: Int
}

public enum CodexThreadImporter {
    public static func merge(
        _ threads: [CodexThreadSummary],
        into existingSessions: [PersistedSession],
        nextRotationIndex: Int
    ) -> CodexThreadImportResult {
        var sessionsByID = Dictionary(uniqueKeysWithValues: existingSessions.map { ($0.sessionID, $0) })
        var nextIndex = nextRotationIndex
        var addedCount = 0
        var updatedCount = 0

        for thread in threads where SessionSourcePolicy.isAllowedAppServerKind(thread.sourceKind) {
            let threadName = TitleBuilder.summary(from: thread.name)
            if var existing = sessionsByID[thread.id] {
                existing.projectPath = thread.cwd
                existing.projectName = TitleBuilder.projectName(from: thread.cwd)
                existing.codexThreadName = threadName
                existing.lastUpdatedAt = max(existing.lastUpdatedAt, thread.updatedAt)
                if existing.settingsListSortAt == nil {
                    existing.settingsListSortAt = thread.updatedAt
                }
                sessionsByID[thread.id] = existing
                updatedCount += 1
            } else {
                sessionsByID[thread.id] = PersistedSession(
                    sessionID: thread.id,
                    projectPath: thread.cwd,
                    projectName: TitleBuilder.projectName(from: thread.cwd),
                    codexThreadName: threadName,
                    isIncludedInHUD: false,
                    discoveredAt: thread.createdAt,
                    lastUpdatedAt: thread.updatedAt,
                    settingsListSortAt: thread.updatedAt,
                    rotationIndex: nextIndex
                )
                nextIndex += 1
                addedCount += 1
            }
        }

        return CodexThreadImportResult(
            sessions: sessionsByID.values.sorted { $0.rotationIndex < $1.rotationIndex },
            addedCount: addedCount,
            updatedCount: updatedCount,
            nextRotationIndex: nextIndex
        )
    }
}

public enum CodexAppServerError: LocalizedError, Equatable {
    case launchFailed(String)
    case connectionClosed
    case timeout
    case invalidResponse
    case server(String)

    public var errorDescription: String? {
        switch self {
        case let .launchFailed(message): return "无法启动 Codex：\(message)"
        case .connectionClosed: return "Codex 会话服务意外关闭"
        case .timeout: return "Codex 会话同步超时"
        case .invalidResponse: return "Codex 返回了无法识别的会话数据"
        case let .server(message): return "Codex 会话服务错误：\(message)"
        }
    }
}

public struct CodexAppServerClient: Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let responseTimeout: TimeInterval
    public let overallTimeout: TimeInterval

    public init(
        executableURL: URL = URL(fileURLWithPath: "/bin/zsh"),
        arguments: [String] = ["-lic", "exec codex app-server --listen stdio://"],
        responseTimeout: TimeInterval = 15,
        overallTimeout: TimeInterval = 30
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.responseTimeout = responseTimeout
        self.overallTimeout = overallTimeout
    }

    public func listThreads() throws -> [CodexThreadSummary] {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let input = Pipe()
        let output = Pipe()
        let errorOutput = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput

        let collector = JSONLineResponseCollector()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { collector.close() }
            else { collector.append(data) }
        }
        errorOutput.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errorOutput.fileHandleForReading.readabilityHandler = nil
            throw CodexAppServerError.launchFailed(error.localizedDescription)
        }

        let overallDeadline = Date(timeIntervalSinceNow: overallTimeout)
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            errorOutput.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
            stop(process)
        }

        try send(
            [
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "traceflow",
                        "title": "Traceflow",
                        "version": "0.1.0",
                    ],
                    "capabilities": [
                        "optOutNotificationMethods": [],
                    ],
                ],
            ],
            to: input.fileHandleForWriting
        )
        _ = try checkedResult(collector.waitForResponse(id: 1, timeout: remainingTimeout(until: overallDeadline)))
        try send(["method": "initialized", "params": [:]], to: input.fileHandleForWriting)

        var allThreads: [CodexThreadSummary] = []
        var cursor: String?
        var requestID = 2
        repeat {
            var params: [String: Any] = [
                "limit": 100,
                "archived": false,
                "sortKey": "updated_at",
                "sortDirection": "desc",
                "sourceKinds": SessionSourcePolicy.allowedAppServerKinds,
            ]
            if let cursor { params["cursor"] = cursor }
            try send(
                ["method": "thread/list", "id": requestID, "params": params],
                to: input.fileHandleForWriting
            )
            let result = try checkedResult(collector.waitForResponse(id: requestID, timeout: remainingTimeout(until: overallDeadline)))
            let page = try CodexThreadListPage.decode(from: result)
            allThreads.append(contentsOf: page.threads)
            cursor = page.nextCursor
            requestID += 1
        } while cursor != nil

        var seen = Set<String>()
        return allThreads.filter { seen.insert($0.id).inserted }
    }

    private func send(_ object: [String: Any], to handle: FileHandle) throws {
        guard JSONSerialization.isValidJSONObject(object) else { throw CodexAppServerError.invalidResponse }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        do { try handle.write(contentsOf: data) }
        catch { throw CodexAppServerError.connectionClosed }
    }

    private func checkedResult(_ response: [String: Any]) throws -> Any {
        if let error = response["error"] as? [String: Any] {
            throw CodexAppServerError.server(error["message"] as? String ?? "未知错误")
        }
        guard let result = response["result"] else { throw CodexAppServerError.invalidResponse }
        return result
    }

    private func remainingTimeout(until deadline: Date) throws -> TimeInterval {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw CodexAppServerError.timeout }
        return min(responseTimeout, remaining)
    }

    private func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let gracefulDeadline = Date(timeIntervalSinceNow: 1)
        while process.isRunning, Date() < gracefulDeadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
    }
}

private final class JSONLineResponseCollector: @unchecked Sendable {
    private let condition = NSCondition()
    private var buffer = Data()
    private var responses: [Int: [String: Any]] = [:]
    private var isClosed = false

    func append(_ data: Data) {
        condition.lock()
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = object["id"] as? Int else { continue }
            responses[id] = object
        }
        condition.broadcast()
        condition.unlock()
    }

    func close() {
        condition.lock()
        isClosed = true
        condition.broadcast()
        condition.unlock()
    }

    func waitForResponse(id: Int, timeout: TimeInterval) throws -> [String: Any] {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }
        while responses[id] == nil, !isClosed {
            guard condition.wait(until: deadline) else { throw CodexAppServerError.timeout }
        }
        if let response = responses.removeValue(forKey: id) { return response }
        throw CodexAppServerError.connectionClosed
    }
}
