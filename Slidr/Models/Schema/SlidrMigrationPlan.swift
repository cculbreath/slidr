/// SlidrMigrationPlan — SwiftData schema migration chain
///
/// Only the most recent schema versions are preserved. Older versions
/// have been removed; git history has them if ever needed.
///
/// Migration chain: V11 → V12 → V13 → V14
///
/// All migrations in this chain are lightweight (additive optional fields).

import SwiftData

enum SlidrMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SlidrSchemaV11.self, SlidrSchemaV12.self, SlidrSchemaV13.self, SlidrSchemaV14.self]
    }

    static var stages: [MigrationStage] {
        [migrateV11toV12, migrateV12toV13, migrateV13toV14]
    }

    // V11 -> V12: Lightweight migration for new filter properties on Playlist
    static let migrateV11toV12 = MigrationStage.lightweight(
        fromVersion: SlidrSchemaV11.self,
        toVersion: SlidrSchemaV12.self
    )

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
}
