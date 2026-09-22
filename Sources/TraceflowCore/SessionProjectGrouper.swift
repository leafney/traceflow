import Foundation

public enum ProjectSelectionState: String, Sendable, Equatable {
    case none
    case partial
    case all
}

public struct SessionProjectGroup: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let projectPath: String?
    public let sessions: [SessionSnapshot]
    public let enabledCount: Int
    public let totalCount: Int
    public let selectionState: ProjectSelectionState
    public let listSortAt: Date

    public init(
        id: String,
        displayName: String,
        projectPath: String?,
        sessions: [SessionSnapshot],
        enabledCount: Int,
        totalCount: Int,
        selectionState: ProjectSelectionState,
        listSortAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.projectPath = projectPath
        self.sessions = sessions
        self.enabledCount = enabledCount
        self.totalCount = totalCount
        self.selectionState = selectionState
        self.listSortAt = listSortAt
    }
}

public enum SessionProjectGrouper {
    public static let unknownProjectKey = "__traceflow_unknown_project__"

    public static func projectKey(for path: String?) -> String {
        normalizedPath(path) ?? unknownProjectKey
    }

    public static func groups(from sessions: [SessionSnapshot]) -> [SessionProjectGroup] {
        let grouped = Dictionary(grouping: sessions) { projectKey(for: $0.persisted.projectPath) }
        return grouped.compactMap { key, values -> SessionProjectGroup? in
            guard !values.isEmpty else { return nil }
            let sortedSessions = values.sorted(by: sessionComesFirst)
            let normalizedProjectPath = key == unknownProjectKey ? nil : key
            let displayName = values.lazy.compactMap { nonEmpty($0.persisted.projectName) }.first
                ?? normalizedProjectPath.flatMap { TitleBuilder.projectName(from: $0) }
                ?? "未知项目"
            let enabledCount = values.filter { $0.persisted.isIncludedInHUD }.count
            let selectionState: ProjectSelectionState
            if enabledCount == 0 { selectionState = .none }
            else if enabledCount == values.count { selectionState = .all }
            else { selectionState = .partial }
            return SessionProjectGroup(
                id: key,
                displayName: displayName,
                projectPath: normalizedProjectPath,
                sessions: sortedSessions,
                enabledCount: enabledCount,
                totalCount: values.count,
                selectionState: selectionState,
                listSortAt: sortedSessions[0].persisted.effectiveSettingsListSortAt
            )
        }.sorted(by: groupComesFirst)
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let trimmed = nonEmpty(path) else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sessionComesFirst(_ lhs: SessionSnapshot, _ rhs: SessionSnapshot) -> Bool {
        let leftDate = lhs.persisted.effectiveSettingsListSortAt
        let rightDate = rhs.persisted.effectiveSettingsListSortAt
        if leftDate != rightDate { return leftDate > rightDate }
        if lhs.persisted.rotationIndex != rhs.persisted.rotationIndex {
            return lhs.persisted.rotationIndex > rhs.persisted.rotationIndex
        }
        return lhs.id < rhs.id
    }

    private static func groupComesFirst(_ lhs: SessionProjectGroup, _ rhs: SessionProjectGroup) -> Bool {
        if lhs.listSortAt != rhs.listSortAt { return lhs.listSortAt > rhs.listSortAt }
        let nameComparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
        return lhs.id < rhs.id
    }
}
