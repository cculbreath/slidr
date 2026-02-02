import SwiftUI
import SwiftData
import OSLog

/// Settings tab for vault management: enable/disable vault mode, manage vaults, security settings.
struct VaultSettingsView: View {
    @State private var manifest: VaultManifest?
    @State private var showingSetupWizard = false
    @State private var showingPasswordChange = false
    @State private var showingDisableSheet = false
    @State private var showingExternalRegistration = false
    @State private var errorMessage: String?

    private var slidrDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Slidr")
    }

    var body: some View {
        Form {
            if let manifest {
                if manifest.vaults.isEmpty {
                    disabledContent
                } else {
                    enabledContent(manifest)
                }
            } else {
                ProgressView("Loading vault settings...")
            }
        }
        .formStyle(.grouped)
        .task { loadManifest() }
        .sheet(isPresented: $showingSetupWizard) {
            VaultSetupWizardView()
        }
        .sheet(isPresented: $showingPasswordChange) {
            VaultPasswordChangeView(slidrDirectory: slidrDirectory) {
                loadManifest()
            }
        }
        .sheet(isPresented: $showingExternalRegistration) {
            ExternalVaultRegistrationView(slidrDirectory: slidrDirectory) {
                loadManifest()
            }
        }
        .sheet(isPresented: $showingDisableSheet) {
            VaultDisableView(slidrDirectory: slidrDirectory)
        }
    }

    // MARK: - Disabled State

    private var disabledContent: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "lock.open")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text("Vault mode is not enabled")
                    .font(.headline)

                Text("Enable vault mode to encrypt your media library with AES-256 and protect it with a password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Enable Vault Mode...") {
                    showingSetupWizard = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    // MARK: - Enabled State

    @ViewBuilder
    private func enabledContent(_ manifest: VaultManifest) -> some View {
        Section("Registered Vaults") {
            ForEach(manifest.vaults) { vault in
                vaultRow(vault)
            }
        }

        Section("Security") {
            Toggle("Save password to Keychain", isOn: manifestBinding(\.useKeychain))
            Toggle("Auto-lock on sleep", isOn: manifestBinding(\.autoLockOnSleep))
            Toggle("Auto-lock on screensaver", isOn: manifestBinding(\.autoLockOnScreensaver))

            Button("Change Password...") {
                showingPasswordChange = true
            }
        }

        Section("External Drives") {
            Button("Register External Drive Vault...") {
                showingExternalRegistration = true
            }
        }

        Section {
            Button("Disable Vault Mode...", role: .destructive) {
                showingDisableSheet = true
            }
        }

        if let errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private func vaultRow(_ vault: VaultConfiguration) -> some View {
        HStack {
            Image(systemName: vault.driveType == .local ? "internaldrive" : "externaldrive")
                .foregroundStyle(.tint)

            VStack(alignment: .leading) {
                Text(vault.name)
                    .font(.headline)
                Text(vault.bundlePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if vault.isEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Manifest Management

    private func loadManifest() {
        let manifestURL = slidrDirectory.appendingPathComponent(VaultManifest.filename)
        if let data = try? Data(contentsOf: manifestURL),
           let loaded = try? JSONDecoder().decode(VaultManifest.self, from: data) {
            manifest = loaded
        } else {
            manifest = .empty
        }
    }

    private func saveManifest() {
        guard let manifest else { return }
        let manifestURL = slidrDirectory.appendingPathComponent(VaultManifest.filename)
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    private func manifestBinding(_ keyPath: WritableKeyPath<VaultManifest, Bool>) -> Binding<Bool> {
        Binding(
            get: { manifest?[keyPath: keyPath] ?? false },
            set: { newValue in
                manifest?[keyPath: keyPath] = newValue
                saveManifest()
            }
        )
    }

}

// MARK: - Disable Vault Sheet

struct VaultDisableView: View {
    let slidrDirectory: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext

    @State private var isDisabling = false
    @State private var showConfirm = true
    @State private var progress = 0.0
    @State private var status = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            if showConfirm {
                confirmContent
            } else {
                progressContent
            }
        }
        .padding(30)
        .frame(width: 480, height: 360)
    }

    private var confirmContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.open.trianglebadge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.red)

            Text("Disable Vault Mode")
                .font(.title2)
                .fontWeight(.bold)

            Text("This will decrypt your library by moving all files back to their standard locations. The encrypted vaults will be deleted.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Slidr will restart after this operation.")
                .font(.caption)
                .foregroundStyle(.orange)

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Disable Vault Mode", role: .destructive) {
                    showConfirm = false
                    Task { await performDisable() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }

    private var progressContent: some View {
        VStack(spacing: 20) {
            Text("Disabling Vault Mode")
                .font(.title2)
                .fontWeight(.bold)

            ProgressView(value: progress)
                .progressViewStyle(.linear)

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)

                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                }
            }

            Spacer()
        }
    }

    private func performDisable() async {
        isDisabling = true
        errorMessage = nil

        do {
            let fm = FileManager.default

            // Load manifest to find vaults
            let service = try VaultService(slidrDirectory: slidrDirectory)
            let localVault = await service.localVault()
            let externalVaults = await service.externalVaults()

            // --- Phase 1: Find mount points ---
            status = "Locating mounted vaults..."
            progress = 0.05

            var localMount: URL?
            if let lv = localVault {
                localMount = await VaultService.findMountPoint(for: lv.bundlePath)
            }

            var externalMounts: [(VaultConfiguration, URL)] = []
            for vault in externalVaults {
                if let mount = await VaultService.findMountPoint(for: vault.bundlePath) {
                    externalMounts.append((vault, mount))
                }
            }

            // --- Phase 2: Copy database back ---
            if let mount = localMount {
                status = "Copying database..."
                progress = 0.1

                let dbSource = mount.appendingPathComponent("Slidr.store")
                let dbDest = slidrDirectory.appendingPathComponent("Slidr.store")

                // Remove any existing file at destination (may be stale/empty)
                for suffix in ["", "-wal", "-shm"] {
                    let dest = URL(fileURLWithPath: dbDest.path + suffix)
                    if fm.fileExists(atPath: dest.path) {
                        try fm.removeItem(at: dest)
                    }
                }

                // Copy (not move — database is actively in use by SwiftData)
                if fm.fileExists(atPath: dbSource.path) {
                    try fm.copyItem(at: dbSource, to: dbDest)
                }
                for suffix in ["-wal", "-shm"] {
                    let src = URL(fileURLWithPath: dbSource.path + suffix)
                    let dst = URL(fileURLWithPath: dbDest.path + suffix)
                    if fm.fileExists(atPath: src.path) {
                        try fm.copyItem(at: src, to: dst)
                    }
                }

                // --- Phase 3: Move thumbnails back ---
                status = "Moving thumbnails..."
                progress = 0.2

                let thumbSource = mount.appendingPathComponent("Thumbnails")
                let thumbDest = slidrDirectory.appendingPathComponent("Thumbnails")
                if fm.fileExists(atPath: thumbSource.path) {
                    if fm.fileExists(atPath: thumbDest.path) {
                        try fm.removeItem(at: thumbDest)
                    }
                    try fm.moveItem(at: thumbSource, to: thumbDest)
                }

                // --- Phase 4: Move transcripts back ---
                status = "Moving transcripts..."
                progress = 0.3

                let transSource = mount.appendingPathComponent("Transcripts")
                let transDest = slidrDirectory.appendingPathComponent("Transcripts")
                if fm.fileExists(atPath: transSource.path) {
                    if fm.fileExists(atPath: transDest.path) {
                        try fm.removeItem(at: transDest)
                    }
                    try fm.moveItem(at: transSource, to: transDest)
                }

                // --- Phase 5: Move local media files back ---
                status = "Moving local media files..."
                progress = 0.35

                let localItems = ((try? modelContext.fetch(FetchDescriptor<MediaItem>())) ?? [])
                    .filter { $0.storageLocation == .local }

                if !localItems.isEmpty {
                    let destLibrary = slidrDirectory.appendingPathComponent("Library")
                    try fm.createDirectory(at: destLibrary, withIntermediateDirectories: true)

                    for (index, item) in localItems.enumerated() {
                        let sourceURL = mount.appendingPathComponent("Library").appendingPathComponent(item.relativePath)
                        let destURL = destLibrary.appendingPathComponent(item.relativePath)

                        if fm.fileExists(atPath: sourceURL.path) {
                            try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try fm.moveItem(at: sourceURL, to: destURL)
                        }

                        if index % 50 == 0 || index == localItems.count - 1 {
                            let fraction = Double(index + 1) / Double(localItems.count)
                            progress = 0.35 + fraction * 0.2
                            status = "Moving local media... \(index + 1)/\(localItems.count)"
                        }
                    }
                }
            }

            // --- Phase 6: Move external media files back ---
            if !externalMounts.isEmpty {
                status = "Moving external media files..."
                progress = 0.6

                let externalItems = ((try? modelContext.fetch(FetchDescriptor<MediaItem>())) ?? [])
                    .filter { $0.storageLocation == .external }

                if !externalItems.isEmpty, let extRoot = library.externalLibraryRoot {
                    // External media goes back to the configured external library root
                    for (index, item) in externalItems.enumerated() {
                        // Try each external mount to find the file
                        for (_, mount) in externalMounts {
                            let sourceURL = mount.appendingPathComponent(item.relativePath)
                            if fm.fileExists(atPath: sourceURL.path) {
                                let destURL = extRoot.appendingPathComponent(item.relativePath)
                                try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                                try fm.moveItem(at: sourceURL, to: destURL)
                                break
                            }
                        }

                        if index % 50 == 0 || index == externalItems.count - 1 {
                            let fraction = Double(index + 1) / Double(externalItems.count)
                            progress = 0.6 + fraction * 0.15
                            status = "Moving external media... \(index + 1)/\(externalItems.count)"
                        }
                    }
                }
            }

            // --- Phase 7: Force unmount all vaults ---
            status = "Unmounting vaults..."
            progress = 0.8

            if let mount = localMount {
                try await forceDetach(mount)
            }
            for (_, mount) in externalMounts {
                try await forceDetach(mount)
            }

            // --- Phase 8: Delete sparse bundles ---
            status = "Deleting vault files..."
            progress = 0.85

            if let lv = localVault {
                let bundleURL = URL(fileURLWithPath: lv.bundlePath)
                if fm.fileExists(atPath: bundleURL.path) {
                    try fm.removeItem(at: bundleURL)
                }
            }
            for vault in externalVaults {
                let bundleURL = URL(fileURLWithPath: vault.bundlePath)
                if fm.fileExists(atPath: bundleURL.path) {
                    try fm.removeItem(at: bundleURL)
                }
            }

            // --- Phase 9: Clear manifest and keychain ---
            status = "Cleaning up..."
            progress = 0.9

            let manifestURL = slidrDirectory.appendingPathComponent(VaultManifest.filename)
            if fm.fileExists(atPath: manifestURL.path) {
                try fm.removeItem(at: manifestURL)
            }
            KeychainHelper.deletePassword()

            // --- Phase 10: Restart ---
            progress = 1.0
            status = "Restarting Slidr..."

            try await Task.sleep(for: .milliseconds(500))
            relaunchApp()

        } catch {
            Logger.vault.error("Failed to disable vault mode: \(error.localizedDescription)")
            errorMessage = "Failed: \(error.localizedDescription)"
            isDisabling = false
        }
    }

    private func forceDetach(_ mountPoint: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path, "-force"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
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

// MARK: - Password Change Sheet

struct VaultPasswordChangeView: View {
    let slidrDirectory: URL
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isChanging = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Change Vault Password")
                .font(.title2)
                .fontWeight(.bold)

            VStack(spacing: 12) {
                SecureField("Current Password", text: $currentPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("New Password", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm New Password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(width: 300)

            if !newPassword.isEmpty && !confirmPassword.isEmpty && newPassword != confirmPassword {
                Text("Passwords do not match")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Change Password") {
                    Task { await changePassword() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canChange)
            }
        }
        .padding(30)
        .frame(width: 400)
    }

    private var canChange: Bool {
        !currentPassword.isEmpty && !newPassword.isEmpty && newPassword == confirmPassword && newPassword.count >= 8 && !isChanging
    }

    private func changePassword() async {
        isChanging = true
        errorMessage = nil

        do {
            let service = try VaultService(slidrDirectory: slidrDirectory)
            try await service.changeAllPasswords(oldPassword: currentPassword, newPassword: newPassword)

            // Update Keychain if it was stored
            if KeychainHelper.loadPassword() != nil {
                try? KeychainHelper.savePassword(newPassword)
            }

            onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isChanging = false
        }
    }
}

// MARK: - External Vault Registration Sheet

struct ExternalVaultRegistrationView: View {
    let slidrDirectory: URL
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext

    @State private var selectedDrive: URL?
    @State private var password = ""
    @State private var availableDrives: [URL] = []
    @State private var isWorking = false
    @State private var migrationProgress = 0.0
    @State private var migrationStatus = ""
    @State private var errorMessage: String?
    @State private var externalItemCount = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("Register External Drive Vault")
                .font(.title2)
                .fontWeight(.bold)

            Text("Select the external drive where your Slidr media lives. All external library files tracked in the database will be moved into the encrypted vault.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if availableDrives.isEmpty {
                Text("No external drives detected")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                List(availableDrives, id: \.path, selection: $selectedDrive) { drive in
                    HStack {
                        Image(systemName: "externaldrive")
                        Text(drive.lastPathComponent)
                    }
                    .tag(drive)
                }
                .frame(height: 100)
            }

            if let extRoot = library.externalLibraryRoot {
                HStack {
                    Text("External library root:")
                        .font(.callout)
                    Text(extRoot.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Text("\(externalItemCount) media items to migrate")
                    .font(.callout)
                    .foregroundStyle(externalItemCount > 0 ? .primary : .secondary)
            } else {
                Text("No external library configured")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SecureField("Vault Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            Text("Use the same password as your local vault.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isWorking {
                VStack(spacing: 8) {
                    ProgressView(value: migrationProgress)
                        .progressViewStyle(.linear)
                    Text(migrationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .disabled(isWorking)
                Spacer()
                Button("Create Vault & Migrate") {
                    Task { await createExternalVault() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDrive == nil || password.isEmpty || isWorking)
            }
        }
        .padding(30)
        .frame(width: 520, height: 500)
        .task {
            availableDrives = ExternalDriveManager.mountedExternalDrives()
            externalItemCount = countExternalItems()
        }
    }

    private func countExternalItems() -> Int {
        let allItems = (try? modelContext.fetch(FetchDescriptor<MediaItem>())) ?? []
        return allItems.filter { $0.storageLocation == .external }.count
    }

    private func fetchExternalItems() -> [MediaItem] {
        let allItems = (try? modelContext.fetch(FetchDescriptor<MediaItem>())) ?? []
        return allItems.filter { $0.storageLocation == .external }
    }

    private func createExternalVault() async {
        guard let drive = selectedDrive else { return }
        guard let extRoot = library.externalLibraryRoot else {
            errorMessage = "No external library root configured. Configure an external drive in Import settings first."
            return
        }

        isWorking = true
        errorMessage = nil

        do {
            let fm = FileManager.default

            // 1. Create vault
            migrationStatus = "Creating encrypted vault..."
            migrationProgress = 0.05

            let service = try VaultService(slidrDirectory: slidrDirectory)
            let bundleURL = drive.appendingPathComponent("Slidr-Vault.sparsebundle")
            let name = "External - \(drive.lastPathComponent)"

            let config = try await service.createVault(
                name: name,
                at: bundleURL,
                password: password
            )

            try await service.addVault(config)

            // 2. Mount vault
            migrationStatus = "Mounting vault..."
            migrationProgress = 0.1

            let mountPoint = try await service.mountVault(config.id, password: password)

            // 3. Query external media items from the database
            migrationStatus = "Querying external media from database..."
            migrationProgress = 0.15

            let externalItems = fetchExternalItems()

            if externalItems.isEmpty {
                migrationStatus = "No external media to migrate"
                migrationProgress = 0.9
            } else {
                migrationStatus = "Moving \(externalItems.count) files into vault..."
                migrationProgress = 0.2

                let totalItems = externalItems.count
                var moved = 0
                var skipped = 0

                for (index, item) in externalItems.enumerated() {
                    // Resolve current absolute path: externalLibraryRoot + relativePath
                    let sourceURL = extRoot.appendingPathComponent(item.relativePath)
                    // Destination in vault uses the same relativePath
                    let destURL = mountPoint.appendingPathComponent(item.relativePath)

                    if fm.fileExists(atPath: sourceURL.path) {
                        // Create parent directory in vault
                        try fm.createDirectory(
                            at: destURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try fm.moveItem(at: sourceURL, to: destURL)
                        moved += 1
                    } else {
                        skipped += 1
                    }

                    if index % 25 == 0 || index == totalItems - 1 {
                        let fraction = Double(index + 1) / Double(totalItems)
                        migrationProgress = 0.2 + fraction * 0.7
                        migrationStatus = "Moving files... \(index + 1)/\(totalItems) (\(skipped) skipped)"
                    }
                }

                Logger.vault.info("External vault migration: \(moved) moved, \(skipped) skipped (not found on disk)")
            }

            // 4. Clean up empty directories left behind
            migrationStatus = "Cleaning up..."
            migrationProgress = 0.95

            cleanupEmptyDirectories(at: extRoot)

            // 5. Unmount vault
            try await service.unmountVault(config.id)

            migrationProgress = 1.0
            migrationStatus = "Complete"

            onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isWorking = false
        }
    }

    /// Recursively removes empty directories from bottom up, but does not remove the root itself.
    private func cleanupEmptyDirectories(at url: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                removeEmptySubdirectories(at: item)
            }
        }
    }

    private func removeEmptySubdirectories(at url: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                removeEmptySubdirectories(at: item)
            }
        }

        // Remove if now empty
        if let remaining = try? fm.contentsOfDirectory(atPath: url.path), remaining.isEmpty {
            try? fm.removeItem(at: url)
        }
    }
}
