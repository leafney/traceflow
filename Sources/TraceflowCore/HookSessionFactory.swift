import Foundation

public enum HookSessionFactory {
    public static func makePersistedSession(
        sessionID: String,
        cwd: String?,
        now: Date,
        rotationIndex: Int
    ) -> PersistedSession {
        PersistedSession(
            sessionID: sessionID,
            projectPath: cwd,
            projectName: TitleBuilder.projectName(from: cwd),
            isIncludedInHUD: false,
            discoveredAt: now,
            lastUpdatedAt: now,
            settingsListSortAt: now,
            rotationIndex: rotationIndex
        )
    }
}
