import Foundation

enum ProductionType: String, Codable, Sendable, CaseIterable {
    case homemade = "Homemade"
    case creator = "Creator"
    case professional = "Professional"

    var displayName: String {
        rawValue
    }

    var iconName: String {
        switch self {
        case .homemade: return "house.fill"
        case .creator: return "person.crop.rectangle.fill"
        case .professional: return "film.fill"
        }
    }
}
