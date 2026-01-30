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
