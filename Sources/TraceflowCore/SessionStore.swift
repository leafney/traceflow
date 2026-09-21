import Foundation

public struct SessionDocument: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public var sessions: [PersistedSession]

    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", sessions }
    public init(schemaVersion: Int = 1, sessions: [PersistedSession]) { self.schemaVersion = schemaVersion; self.sessions = sessions }
}

public final class SessionStore: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "io.traceflow.sessions")
    public init(url: URL) { self.url = url }

    public func load() throws -> [PersistedSession] {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder.traceflow.decode(SessionDocument.self, from: data)
            guard document.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
            return document.sessions
        }
    }

    public func save(_ sessions: [PersistedSession]) throws {
        try queue.sync {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder.traceflow.encode(SessionDocument(sessions: sessions))
            _ = try JSONDecoder.traceflow.decode(SessionDocument.self, from: data)
            let temporary = directory.appendingPathComponent(".sessions-\(UUID().uuidString).tmp")
            try data.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary) }
            else { try FileManager.default.moveItem(at: temporary, to: url) }
        }
    }
}

extension JSONEncoder {
    static var traceflow: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}

extension JSONDecoder {
    static var traceflow: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
}
