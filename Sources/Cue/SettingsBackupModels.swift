import CueCore

struct SettingsBackupPreview: Sendable {
    struct Row: Sendable, Identifiable {
        let section: SettingsBackupSection
        let current: String
        let incoming: String
        let details: [String]
        var id: SettingsBackupSection { section }
    }
    let rows: [Row]
    let warnings: [String]
}

struct SettingsBackupApplyResult: Sendable {
    enum KeyStatus: Sendable { case excluded, restored, failed }
    enum RetentionStatus: Sendable { case unchanged, applied, cleanupFailed }
    let appliedSections: Set<SettingsBackupSection>
    let keyStatus: KeyStatus
    let retentionStatus: RetentionStatus
}
