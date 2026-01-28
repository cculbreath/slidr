import Foundation

enum ImportMode: String, Codable, Sendable, CaseIterable {
    case copy = "Copy"
    case move = "Move"
    case reference = "Reference"

    var displayName: String {
        switch self {
        case .copy: return "Copy to Library"
        case .move: return "Move to Library"
        case .reference: return "Reference in Place"
        }
    }

    var description: String {
        switch self {
        case .copy: return "Files are copied into the library. Originals remain in their source location."
        case .move: return "Files are moved into the library. Originals are deleted from the source location."
        case .reference: return "Files remain in their original location and are referenced by the library. Referenced files become unavailable if moved or deleted."
        }
    }
}
