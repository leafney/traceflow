import Foundation

public enum TitleBuilder {
    public static func projectName(from path: String?) -> String? {
        guard let path else { return nil }
        let value = URL(fileURLWithPath: path).standardizedFileURL.lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public static func summary(from prompt: String?, limit: Int = 30) -> String? {
        guard let prompt else { return nil }
        let normalized = prompt.replacingOccurrences(of: "\r\n", with: "\n")
        guard var line = normalized.components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else { return nil }

        let marker = try? NSRegularExpression(pattern: #"^(?:#{1,6}\s+|[-*+]\s+|>\s*|\d+[.)]\s+)"#)
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        line = marker?.stringByReplacingMatches(in: line, range: range, withTemplate: "") ?? line
        line = line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !line.isEmpty else { return nil }
        return String(line.prefix(limit))
    }

    public static func displayTitle(projectName: String?, conversationSummary: String?) -> String {
        let project = nonEmpty(projectName)
        let summary = nonEmpty(conversationSummary)
        switch (project, summary) {
        case let (.some(project), .some(summary)): return "\(project) · \(summary)"
        case let (.none, .some(summary)): return summary
        case let (.some(project), .none): return project
        case (.none, .none): return "未知会话"
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
