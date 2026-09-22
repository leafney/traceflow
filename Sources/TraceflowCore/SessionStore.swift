import Foundation

public enum SessionDataHealth: Sendable, Equatable {
    case healthy
    case corrupted(String)
    case unwritable(String)

    public var allowsSaving: Bool {
        if case .healthy = self { return true }
        return false
    }
}

public enum SessionStoreError: LocalizedError, Equatable {
    case writeProtected
    case noCorruptFile
    case backupVerificationFailed

    public var errorDescription: String? {
        switch self {
        case .writeProtected: "会话数据处于保护状态，未写入文件"
        case .noCorruptFile: "找不到需要重建的会话数据文件"
        case .backupVerificationFailed: "会话数据备份校验失败，未执行重建"
        }
    }
}

public struct SessionDocument: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public var sessions: [PersistedSession]

    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", sessions }
    public init(schemaVersion: Int = 1, sessions: [PersistedSession]) { self.schemaVersion = schemaVersion; self.sessions = sessions }
}

public final class SessionStore: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "io.traceflow.sessions")
    private var storedHealth: SessionDataHealth = .healthy
    public init(url: URL) { self.url = url }

    public var health: SessionDataHealth { queue.sync { storedHealth } }

    public func load() throws -> [PersistedSession] {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: url.path) else {
                storedHealth = .healthy
                return []
            }
            do {
                let data = try Data(contentsOf: url)
                let document = try JSONDecoder.traceflow.decode(SessionDocument.self, from: data)
                guard document.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
                storedHealth = .healthy
                return document.sessions
            } catch {
                storedHealth = .corrupted(error.localizedDescription)
                throw error
            }
        }
    }

    public func save(_ sessions: [PersistedSession]) throws {
        try queue.sync {
            guard storedHealth.allowsSaving else { throw SessionStoreError.writeProtected }
            try saveUnlocked(sessions)
        }
    }

    public func retrySave(_ sessions: [PersistedSession]) throws {
        try queue.sync {
            guard case .unwritable = storedHealth else {
                guard storedHealth.allowsSaving else { throw SessionStoreError.writeProtected }
                return try saveUnlocked(sessions)
            }
            try saveUnlocked(sessions)
        }
    }

    @discardableResult
    public func backupAndRebuild() throws -> URL {
        try queue.sync {
            guard case .corrupted = storedHealth,
                  FileManager.default.fileExists(atPath: url.path) else { throw SessionStoreError.noCorruptFile }
            let sourceData = try Data(contentsOf: url)
            let formatter = ISO8601DateFormatter()
            let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = url.deletingLastPathComponent().appendingPathComponent("sessions.json.corrupt-\(stamp)-\(UUID().uuidString.prefix(8)).backup")
            try sourceData.write(to: backup, options: [.atomic])
            guard try Data(contentsOf: backup) == sourceData else { throw SessionStoreError.backupVerificationFailed }
            do {
                try writeDocumentUnlocked(SessionDocument(sessions: []))
                storedHealth = .healthy
                return backup
            } catch {
                storedHealth = .corrupted(error.localizedDescription)
                throw error
            }
        }
    }

    private func saveUnlocked(_ sessions: [PersistedSession]) throws {
        do {
            try writeDocumentUnlocked(SessionDocument(sessions: sessions))
            storedHealth = .healthy
        } catch {
            storedHealth = .unwritable(error.localizedDescription)
            throw error
        }
    }

    private func writeDocumentUnlocked(_ document: SessionDocument) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder.traceflow.encode(document)
        _ = try JSONDecoder.traceflow.decode(SessionDocument.self, from: data)
        let temporary = directory.appendingPathComponent(".sessions-\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary) }
            else { try FileManager.default.moveItem(at: temporary, to: url) }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

extension JSONEncoder {
    static var traceflow: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}

extension JSONDecoder {
    static var traceflow: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
}
