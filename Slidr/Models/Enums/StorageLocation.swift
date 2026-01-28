import Foundation

enum StorageLocation: String, Codable, Sendable, CaseIterable {
    case local = "Local"
    case external = "External"
    case referenced = "Referenced"

    var displayName: String {
        switch self {
        case .local: return "Local Library"
        case .external: return "External Library"
        case .referenced: return "Referenced"
        }
    }

    var icon: String {
        switch self {
        case .local: return "internaldrive"
        case .external: return "externaldrive"
        case .referenced: return "link"
        }
    }
}

struct ExternalDriveManager {
    static func mountedExternalDrives() -> [URL] {
        let fileManager = FileManager.default
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        guard let volumes = try? fileManager.contentsOfDirectory(
            at: volumesURL,
            includingPropertiesForKeys: [.volumeIsRemovableKey, .volumeIsInternalKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return volumes.filter { url in
            guard let resources = try? url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsInternalKey]) else { return false }
            return resources.volumeIsRemovable == true || resources.volumeIsInternal == false
        }
    }

    static func isExternalDrive(_ url: URL) -> Bool {
        let path = url.path
        return path.hasPrefix("/Volumes/") && !path.hasPrefix("/Volumes/Macintosh HD")
    }

    static func volumeName(for url: URL) -> String? {
        guard isExternalDrive(url) else { return nil }
        let components = url.pathComponents
        guard components.count >= 3 else { return nil }
        return components[2]
    }

    static func isMounted(volumeName: String) -> Bool {
        let volumeURL = URL(fileURLWithPath: "/Volumes/\(volumeName)")
        return FileManager.default.fileExists(atPath: volumeURL.path)
    }
}
