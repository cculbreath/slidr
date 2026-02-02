/// SlidrMigrationPlan — SwiftData schema migration chain
///
/// Only the most recent schema versions are preserved. Older versions
/// have been removed; git history has them if ever needed.
///
/// Migration chain: V12 → V13 → V14 → V15
///
/// All migrations in this chain are lightweight (additive optional fields).

import SwiftData

enum SlidrMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SlidrSchemaV12.self, SlidrSchemaV13.self, SlidrSchemaV14.self, SlidrSchemaV15.self]
    }

    static var stages: [MigrationStage] {
        [migrateV12toV13, migrateV13toV14, migrateV14toV15]
    }

    // V12 -> V13: Lightweight migration for new browserViewModeRaw on AppSettings
    static let migrateV12toV13 = MigrationStage.lightweight(
        fromVersion: SlidrSchemaV12.self,
        toVersion: SlidrSchemaV13.self
    )

    // V13 -> V14: Lightweight migration for AI processing properties on AppSettings
    static let migrateV13toV14 = MigrationStage.lightweight(
        fromVersion: SlidrSchemaV13.self,
        toVersion: SlidrSchemaV14.self
    )

    // V14 -> V15: Lightweight migration for filterSources on Playlist
    static let migrateV14toV15 = MigrationStage.lightweight(
        fromVersion: SlidrSchemaV14.self,
        toVersion: SlidrSchemaV15.self
    )
}
