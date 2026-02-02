import SwiftUI
import SwiftData
import OSLog

/// Multi-step wizard for first-time vault setup and data migration.
/// Uses the database to determine which files to migrate rather than filesystem enumeration.
struct VaultSetupWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext

    @State private var step: Step = .welcome
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var useKeychain = true
    @State private var autoLockOnSleep = true
    @State private var autoLockOnScreensaver = true
    @State private var migrateExternal = true

    @State private var isMigrating = false
    @State private var migrationProgress = 0.0
    @State private var migrationStatus = ""
    @State private var errorMessage: String?

    @State private var localItemCount = 0
    @State private var externalItemCount = 0
    @State private var hasExternalLibrary = false

    enum Step: Int, CaseIterable {
        case welcome
        case passwordSetup
        case configuration
        case migration
        case complete
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.top, 20)

            Spacer()

            Group {
                switch step {
                case .welcome: welcomeContent
                case .passwordSetup: passwordContent
                case .configuration: configContent
                case .migration: migrationContent
                case .complete: completeContent
                }
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 40)

            Spacer()

            // Navigation
            HStack {
                if step != .welcome && step != .complete && !isMigrating {
                    Button("Back") {
                        withAnimation { step = Step(rawValue: step.rawValue - 1)! }
                    }
                }

                Spacer()

                if step == .complete {
                    Button("Quit & Relaunch") {
                        relaunchApp()
                    }
                    .buttonStyle(.borderedProminent)
                } else if step == .migration {
                    Button("Begin Migration") {
                        Task { await performFullMigration() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isMigrating)
                } else {
                    Button("Next") {
                        withAnimation { step = Step(rawValue: step.rawValue + 1)! }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canProceed)
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 520)
        .task {
            loadCounts()
        }
    }

    // MARK: - Step Views

    private var welcomeContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Enable Vault Mode")
                .font(.title)
                .fontWeight(.bold)

            Text("Encrypt your media library with AES-256 encryption and password protection.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Label("Database, thumbnails, and media encrypted at rest", systemImage: "checkmark.circle.fill")
                Label("Single password for all vault locations", systemImage: "checkmark.circle.fill")
                Label("Auto-lock on sleep and screensaver", systemImage: "checkmark.circle.fill")
                Label("External drive vault support", systemImage: "checkmark.circle.fill")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Text("Your existing library will be migrated into the encrypted vault.")
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }
    }

    private var passwordContent: some View {
        VStack(spacing: 20) {
            Text("Create Vault Password")
                .font(.title2)
                .fontWeight(.bold)

            Text("Choose a strong password. There is no recovery mechanism — if you forget this password, your data cannot be recovered.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)

                if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                    Text("Passwords do not match")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !password.isEmpty && password.count < 8 {
                    Text("Password must be at least 8 characters")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 300)

            Toggle("Save password to Keychain", isOn: $useKeychain)
                .toggleStyle(.checkbox)
        }
    }

    private var configContent: some View {
        VStack(spacing: 20) {
            Text("Security & Migration")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Auto-lock on system sleep", isOn: $autoLockOnSleep)
                    .toggleStyle(.checkbox)

                Toggle("Auto-lock when screensaver starts", isOn: $autoLockOnScreensaver)
                    .toggleStyle(.checkbox)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Migration Summary")
                    .font(.headline)

                Label("\(localItemCount) local media files", systemImage: "internaldrive")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Label("Database, thumbnails, and transcripts", systemImage: "cylinder")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if hasExternalLibrary {
                    Divider()

                    Label("\(externalItemCount) external media files", systemImage: "externaldrive")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Toggle("Also migrate external library into vault", isOn: $migrateExternal)
                        .toggleStyle(.checkbox)

                    if migrateExternal {
                        Text("A separate encrypted vault will be created on the external drive.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var migrationContent: some View {
        VStack(spacing: 20) {
            if isMigrating {
                Text("Migrating Library")
                    .font(.title2)
                    .fontWeight(.bold)

                ProgressView(value: migrationProgress)
                    .progressViewStyle(.linear)

                Text(migrationStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Ready to Migrate")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Your existing library will be moved into an encrypted vault. This is a one-time operation.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var completeContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Vault Setup Complete")
                .font(.title2)
                .fontWeight(.bold)

            Text("Slidr needs to restart. On next launch, you'll be asked to unlock your vault.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Logic

    private var canProceed: Bool {
        switch step {
        case .welcome: true
        case .passwordSetup: !password.isEmpty && password == confirmPassword && password.count >= 8
        case .configuration: true
        case .migration: !isMigrating
        case .complete: false
        }
    }

    private func loadCounts() {
        // Fetch all items and filter in memory — SwiftData predicates
        // cannot reliably compare enum properties at runtime.
        let allItems = (try? modelContext.fetch(FetchDescriptor<MediaItem>())) ?? []
        localItemCount = allItems.filter { $0.storageLocation == .local }.count
        externalItemCount = allItems.filter { $0.storageLocation == .external }.count
        hasExternalLibrary = library.externalLibraryRoot != nil && externalItemCount > 0

        Logger.vault.info("Wizard loadCounts: \(localItemCount) local, \(externalItemCount) external, extRoot=\(library.externalLibraryRoot?.path ?? "nil")")
    }

    // MARK: - Full Migration

    private func performFullMigration() async {
        isMigrating = true
        errorMessage = nil

        do {
            let slidrDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Slidr")
            let vaultService = try VaultService(slidrDirectory: slidrDir)

            // Pre-fetch ALL items from the database before the local migration
            // moves the .store file (which invalidates the modelContext).
            let allItems = (try? modelContext.fetch(FetchDescriptor<MediaItem>())) ?? []
            let localItems = allItems.filter { $0.storageLocation == .local }
            let externalItems = allItems.filter { $0.storageLocation == .external }

            Logger.vault.info("Pre-fetched \(localItems.count) local, \(externalItems.count) external items for migration")

            // Phase 1: Local vault
            try await migrateLocalVault(slidrDir: slidrDir, vaultService: vaultService, items: localItems)

            // Phase 2: External vault (if opted in)
            if hasExternalLibrary && migrateExternal {
                try await migrateExternalVault(vaultService: vaultService, items: externalItems)
            }

            // Save manifest settings
            migrationStatus = "Saving configuration..."
            try await vaultService.updateManifest { manifest in
                manifest.useKeychain = useKeychain
                manifest.autoLockOnSleep = autoLockOnSleep
                manifest.autoLockOnScreensaver = autoLockOnScreensaver
            }

            if useKeychain {
                try? KeychainHelper.savePassword(password)
            }

            migrationProgress = 1.0
            migrationStatus = "Complete"

            withAnimation {
                step = .complete
            }

        } catch {
            Logger.vault.error("Vault migration failed: \(error.localizedDescription)")
            errorMessage = "Migration failed: \(error.localizedDescription)"
            isMigrating = false
        }
    }

    // MARK: - Local Vault Migration

    private func migrateLocalVault(slidrDir: URL, vaultService: VaultService, items localItems: [MediaItem]) async throws {
        let fm = FileManager.default
        let externalPhaseWeight: Double = (hasExternalLibrary && migrateExternal) ? 0.5 : 0.0
        let localPhaseWeight: Double = 1.0 - externalPhaseWeight

        // Create local vault
        migrationStatus = "Creating local encrypted vault..."
        migrationProgress = 0.02 * localPhaseWeight

        let bundleURL = slidrDir.appendingPathComponent("Slidr-Vault.sparsebundle")
        let vaultConfig = try await vaultService.createVault(
            name: "Local Vault",
            at: bundleURL,
            password: password
        )
        try await vaultService.addVault(vaultConfig)

        // Mount
        migrationStatus = "Mounting local vault..."
        migrationProgress = 0.05 * localPhaseWeight

        let mountPoint = try await vaultService.mountVault(vaultConfig.id, password: password)

        // Create directory structure
        try fm.createDirectory(at: mountPoint.appendingPathComponent("Library/Local"), withIntermediateDirectories: true)
        try fm.createDirectory(at: mountPoint.appendingPathComponent("Thumbnails"), withIntermediateDirectories: true)
        try fm.createDirectory(at: mountPoint.appendingPathComponent("Transcripts"), withIntermediateDirectories: true)

        // Move database first (before moving media files)
        migrationStatus = "Moving database..."
        migrationProgress = 0.1 * localPhaseWeight

        let dbSource = slidrDir.appendingPathComponent("Slidr.store")
        let dbDest = mountPoint.appendingPathComponent("Slidr.store")
        if fm.fileExists(atPath: dbSource.path) {
            try fm.moveItem(at: dbSource, to: dbDest)
        }
        for suffix in ["-wal", "-shm"] {
            let src = URL(fileURLWithPath: dbSource.path + suffix)
            let dst = URL(fileURLWithPath: dbDest.path + suffix)
            if fm.fileExists(atPath: src.path) {
                try fm.moveItem(at: src, to: dst)
            }
        }

        // Move local media files using database-resolved paths
        if !localItems.isEmpty {
            let libraryRoot = library.libraryRoot
            let totalItems = localItems.count
            var moved = 0
            var skipped = 0

            for (index, item) in localItems.enumerated() {
                let sourceURL = libraryRoot.appendingPathComponent(item.relativePath)
                let destURL = mountPoint.appendingPathComponent("Library").appendingPathComponent(item.relativePath)

                if fm.fileExists(atPath: sourceURL.path) {
                    try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: sourceURL, to: destURL)
                    moved += 1
                } else {
                    skipped += 1
                }

                if index % 25 == 0 || index == totalItems - 1 {
                    let fraction = Double(index + 1) / Double(totalItems)
                    migrationProgress = (0.15 + fraction * 0.45) * localPhaseWeight
                    migrationStatus = "Moving local media... \(index + 1)/\(totalItems)"
                }
            }

            Logger.vault.info("Local vault migration: \(moved) moved, \(skipped) skipped")
        }

        // Move thumbnails (wholesale — cache, not individually tracked)
        migrationStatus = "Moving thumbnails..."
        migrationProgress = 0.7 * localPhaseWeight

        let thumbSource = slidrDir.appendingPathComponent("Thumbnails")
        let thumbDest = mountPoint.appendingPathComponent("Thumbnails")
        if fm.fileExists(atPath: thumbSource.path) {
            try? fm.removeItem(at: thumbDest)
            try fm.moveItem(at: thumbSource, to: thumbDest)
        }

        // Move transcripts (wholesale)
        migrationStatus = "Moving transcripts..."
        migrationProgress = 0.8 * localPhaseWeight

        let transSource = slidrDir.appendingPathComponent("Transcripts")
        let transDest = mountPoint.appendingPathComponent("Transcripts")
        if fm.fileExists(atPath: transSource.path) {
            try? fm.removeItem(at: transDest)
            try fm.moveItem(at: transSource, to: transDest)
        }

        // Clean up empty Library directory left behind
        let oldLibrary = slidrDir.appendingPathComponent("Library")
        if fm.fileExists(atPath: oldLibrary.path) {
            try? fm.removeItem(at: oldLibrary)
        }

        // Unmount local vault
        migrationStatus = "Unmounting local vault..."
        migrationProgress = 0.9 * localPhaseWeight
        try await vaultService.unmountVault(vaultConfig.id)
    }

    // MARK: - External Vault Migration

    private func migrateExternalVault(vaultService: VaultService, items externalItems: [MediaItem]) async throws {
        guard let extRoot = library.externalLibraryRoot else { return }
        let fm = FileManager.default

        let baseProgress = 0.5  // local phase used first half

        // Determine the drive the external library is on
        let drive = extRoot.deletingLastPathComponent()

        // Create external vault on same drive
        migrationStatus = "Creating external encrypted vault..."
        migrationProgress = baseProgress + 0.02

        let bundleURL: URL
        // Put the sparse bundle at the drive root (e.g., /Volumes/Library/Slidr-Vault.sparsebundle)
        if extRoot.pathComponents.count >= 3 {
            let driveRoot = URL(fileURLWithPath: "/Volumes/\(extRoot.pathComponents[2])")
            bundleURL = driveRoot.appendingPathComponent("Slidr-Vault.sparsebundle")
        } else {
            bundleURL = drive.appendingPathComponent("Slidr-Vault.sparsebundle")
        }

        let name = "External - \(bundleURL.deletingLastPathComponent().lastPathComponent)"

        let config = try await vaultService.createVault(
            name: name,
            at: bundleURL,
            password: password
        )
        try await vaultService.addVault(config)

        // Mount
        migrationStatus = "Mounting external vault..."
        migrationProgress = baseProgress + 0.05

        let mountPoint = try await vaultService.mountVault(config.id, password: password)

        if !externalItems.isEmpty {
            let totalItems = externalItems.count
            var moved = 0
            var skipped = 0

            for (index, item) in externalItems.enumerated() {
                let sourceURL = extRoot.appendingPathComponent(item.relativePath)
                let destURL = mountPoint.appendingPathComponent(item.relativePath)

                if fm.fileExists(atPath: sourceURL.path) {
                    try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: sourceURL, to: destURL)
                    moved += 1
                } else {
                    skipped += 1
                }

                if index % 25 == 0 || index == totalItems - 1 {
                    let fraction = Double(index + 1) / Double(totalItems)
                    migrationProgress = baseProgress + 0.1 + fraction * 0.35
                    migrationStatus = "Moving external media... \(index + 1)/\(totalItems)"
                }
            }

            Logger.vault.info("External vault migration: \(moved) moved, \(skipped) skipped")
        }

        // Clean up empty directories on external drive
        migrationStatus = "Cleaning up external drive..."
        migrationProgress = baseProgress + 0.47
        cleanupEmptyDirectories(under: extRoot)

        // Unmount external vault
        migrationStatus = "Unmounting external vault..."
        migrationProgress = baseProgress + 0.49
        try await vaultService.unmountVault(config.id)
    }

    // MARK: - Helpers

    private func cleanupEmptyDirectories(under url: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                cleanupEmptyDirectories(under: item)
                if let remaining = try? fm.contentsOfDirectory(atPath: item.path), remaining.isEmpty {
                    try? fm.removeItem(at: item)
                }
            }
        }
    }

    private func relaunchApp() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        try? task.run()

        NSApplication.shared.terminate(nil)
    }
}
