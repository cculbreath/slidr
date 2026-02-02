import Foundation

enum AITagMode: String, Codable, Sendable, CaseIterable {
    case generateNew
    case constrainToExisting

    var displayName: String {
        switch self {
        case .generateNew: return "Generate New Tags"
        case .constrainToExisting: return "Use Existing Tags Only"
        }
    }
}
