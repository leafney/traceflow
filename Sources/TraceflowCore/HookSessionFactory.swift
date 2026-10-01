import Foundation

public enum HookSessionFactory {
    public static func makePersistedSession(
        sessionID: String,
        cwd: String?,
        now: Date,
        rotationIndex: Int,
        isIncludedInHUD: Bool = false
    ) -> PersistedSession {
        PersistedSession(
            sessionID: sessionID,
            projectPath: cwd,
            projectName: TitleBuilder.projectName(from: cwd),
            isIncludedInHUD: isIncludedInHUD,
            discoveredAt: now,
            lastUpdatedAt: now,
            lastActivityAt: now,
            settingsListSortAt: now,
            rotationIndex: rotationIndex
        )
    }
}
