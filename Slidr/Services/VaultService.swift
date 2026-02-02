import Foundation
import OSLog

/// Manages encrypted sparse bundle vault lifecycle via `hdiutil`.
actor VaultService {
    private let slidrDirectory: URL
    private let manifestURL: URL
    private(set) var manifest: VaultManifest
    private var mountedVaults: [UUID: URL] = [:]

    init(slidrDirectory: URL) throws {
        self.slidrDirectory = slidrDirectory
        self.manifestURL = slidrDirectory.appendingPathComponent(VaultManifest.filename)

        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            self.manifest = try JSONDecoder().decode(VaultManifest.self, from: data)
        } else {
            self.manifest = .empty
        }
    }

    // MARK: - Query

    func isVaultModeEnabled() -> Bool {
        !manifest.vaults.isEmpty
    }

    func localVault() -> VaultConfiguration? {
        manifest.vaults.first { $0.driveType == .local }
    }

    func externalVaults() -> [VaultConfiguration] {
        manifest.vaults.filter { $0.driveType == .external }
    }

    func mountedVaultURL(for vaultID: UUID) -> URL? {
        mountedVaults[vaultID]
    }

    // MARK: - Creation

    func createVault(
        name: String,
        at bundleURL: URL,
        password: String,
        sizeMB: Int? = nil
    ) async throws -> VaultConfiguration {
        guard !FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw VaultError.vaultAlreadyExists(name)
        }

        let parentDir = bundleURL.deletingLastPathComponent()
        try verifyFileSystemSupport(for: parentDir)

        // Default size: 90% of available disk space on the target volume.
        // Sparse bundles only allocate actual data on disk, so a large max
        // size is safe — it just sets the upper limit of the virtual volume.
        let resolvedSizeMB: Int
        if let sizeMB {
            resolvedSizeMB = sizeMB
        } else {
            let values = try parentDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            let availableBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
            let ninetyPercent = Int(Double(availableBytes) * 0.9 / (1024 * 1024))
            resolvedSizeMB = max(ninetyPercent, 50 * 1024) // At least 50 GB
        }
        Logger.vault.info("Creating vault '\(name)' with max size \(resolvedSizeMB) MB")
        try await runHdiutilCreate(at: bundleURL, password: password, sizeMB: resolvedSizeMB)

        let mountName = sanitizeMountName(name)
        let driveType: VaultConfiguration.DriveType = bundleURL.path.hasPrefix("/Volumes/") ? .external : .local
        let volumeUUID = try? bundleURL.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString

        let config = VaultConfiguration(
            id: UUID(),
            name: name,
            bundlePath: bundleURL.path,
            mountPointName: mountName,
            driveType: driveType,
            volumeUUID: volumeUUID,
            createdDate: Date(),
            isEnabled: true
        )

        Logger.vault.info("Created vault '\(name)' at \(bundleURL.path)")
        return config
    }

    // MARK: - Mounting

    func mountVault(_ vaultID: UUID, password: String) async throws -> URL {
        guard let config = manifest.vaults.first(where: { $0.id == vaultID }) else {
            throw VaultError.vaultNotFound(vaultID.uuidString)
        }

        if let existing = mountedVaults[vaultID] {
            return existing
        }

        let bundleURL = URL(fileURLWithPath: config.bundlePath)
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw VaultError.vaultNotFound(config.bundlePath)
        }

        let mountPoint = try await runHdiutilAttach(bundleURL: bundleURL, password: password)
        mountedVaults[vaultID] = mountPoint
        Logger.vault.info("Mounted vault '\(config.name)' at \(mountPoint.path)")
        return mountPoint
    }

    func mountAllEnabled(password: String) async throws -> [UUID: URL] {
        var results: [UUID: URL] = [:]

        for vault in manifest.vaults where vault.isEnabled {
            let bundleURL = URL(fileURLWithPath: vault.bundlePath)
            guard FileManager.default.fileExists(atPath: bundleURL.path) else {
                if vault.driveType == .external {
                    Logger.vault.info("External vault '\(vault.name)' not available (drive disconnected)")
                    continue
                }
                throw VaultError.vaultNotFound(vault.bundlePath)
            }

            let mountPoint = try await mountVault(vault.id, password: password)
            results[vault.id] = mountPoint
        }

        return results
    }

    // MARK: - Unmounting

    func unmountVault(_ vaultID: UUID, force: Bool = false) async throws {
        guard let mountPoint = mountedVaults[vaultID] else { return }
        try await runHdiutilDetach(mountPoint: mountPoint, force: force)
        mountedVaults.removeValue(forKey: vaultID)
        Logger.vault.info("Unmounted vault at \(mountPoint.path)")
    }

    func unmountAllVaults(force: Bool = false) async {
        for (vaultID, mountPoint) in mountedVaults {
            do {
                try await runHdiutilDetach(mountPoint: mountPoint, force: force)
                mountedVaults.removeValue(forKey: vaultID)
            } catch {
                Logger.vault.error("Failed to unmount \(mountPoint.path): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Password Change

    func changePassword(bundleURL: URL, oldPassword: String, newPassword: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["chpass", bundleURL.path]

        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardError = errorPipe

        try process.run()

        // hdiutil chpass reads old password then new password from stdin
        let input = "\(oldPassword)\n\(newPassword)\n\(newPassword)\n"
        if let data = input.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
            try inputPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw VaultError.failedToCreate("Password change failed: \(errorMsg)")
        }
    }

    func changeAllPasswords(oldPassword: String, newPassword: String) async throws {
        for vault in manifest.vaults {
            let bundleURL = URL(fileURLWithPath: vault.bundlePath)
            guard FileManager.default.fileExists(atPath: bundleURL.path) else { continue }
            try await changePassword(bundleURL: bundleURL, oldPassword: oldPassword, newPassword: newPassword)
        }
        Logger.vault.info("Changed password for all vaults")
    }

    // MARK: - Compact

    func compactVault(_ vaultID: UUID) async throws {
        guard let config = manifest.vaults.first(where: { $0.id == vaultID }) else { return }
        guard mountedVaults[vaultID] == nil else {
            Logger.vault.warning("Cannot compact mounted vault")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["compact", config.bundlePath]
        try process.run()
        process.waitUntilExit()
    }

    // MARK: - Manifest Persistence

    func addVault(_ config: VaultConfiguration) throws {
        manifest.vaults.append(config)
        try saveManifest()
    }

    func removeVault(_ vaultID: UUID) throws {
        manifest.vaults.removeAll { $0.id == vaultID }
        try saveManifest()
    }

    func updateManifest(_ updater: (inout VaultManifest) -> Void) throws {
        updater(&manifest)
        try saveManifest()
    }

    private func saveManifest() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    // MARK: - hdiutil Wrappers

    private func runHdiutilCreate(at bundleURL: URL, password: String, sizeMB: Int) async throws {
        let volumeName = bundleURL.deletingPathExtension().lastPathComponent

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "create",
            "-size", "\(sizeMB)m",
            "-type", "SPARSEBUNDLE",
            "-fs", "APFS",
            "-encryption", "AES-256",
            "-stdinpass",
            "-volname", volumeName,
            bundleURL.path
        ]

        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        try process.run()

        if let data = password.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
            try inputPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw VaultError.failedToCreate(msg)
        }
    }

    private func runHdiutilAttach(bundleURL: URL, password: String) async throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", "-stdinpass", "-plist", bundleURL.path]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        if let data = password.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
            try inputPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errorData, encoding: .utf8) ?? "Unknown error"

            if msg.contains("Authentication error") || msg.lowercased().contains("incorrect password")
                || msg.contains("passphrase") {
                throw VaultError.incorrectPassword
            }
            throw VaultError.failedToMount(msg)
        }

        return try parseMountPoint(from: outputPipe.fileHandleForReading.readDataToEndOfFile())
    }

    private func parseMountPoint(from plistData: Data) throws -> URL {
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            throw VaultError.failedToMount("Could not parse hdiutil output")
        }

        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String {
                return URL(fileURLWithPath: mountPoint)
            }
        }

        throw VaultError.failedToMount("Mount point not found in hdiutil output")
    }

    private func runHdiutilDetach(mountPoint: URL, force: Bool) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        var args = ["detach", mountPoint.path]
        if force { args.append("-force") }
        process.arguments = args

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw VaultError.failedToUnmount(msg)
        }
    }

    // MARK: - Mount Point Discovery

    /// Finds the mount point for an already-attached sparse bundle using `hdiutil info`.
    static func findMountPoint(for bundlePath: String) async -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let images = plist["images"] as? [[String: Any]] else {
                return nil
            }

            for image in images {
                guard let imagePath = image["image-path"] as? String,
                      imagePath == bundlePath,
                      let entities = image["system-entities"] as? [[String: Any]] else {
                    continue
                }

                for entity in entities {
                    if let mountPoint = entity["mount-point"] as? String {
                        return URL(fileURLWithPath: mountPoint)
                    }
                }
            }
        } catch {
            Logger.vault.error("Failed to query hdiutil info: \(error.localizedDescription)")
        }

        return nil
    }

    // MARK: - Helpers

    private func verifyFileSystemSupport(for url: URL) throws {
        let values = try url.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey])
        let fsType = (values.volumeLocalizedFormatDescription ?? "").lowercased()

        if fsType.contains("exfat") || fsType.contains("fat32") || fsType.contains("fat16") {
            throw VaultError.unsupportedFileSystem(values.volumeLocalizedFormatDescription ?? fsType)
        }
    }

    private func sanitizeMountName(_ name: String) -> String {
        let sanitized = name
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return "Slidr-\(sanitized)"
    }
}
