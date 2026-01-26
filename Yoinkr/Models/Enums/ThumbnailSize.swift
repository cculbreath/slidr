import Foundation

enum ThumbnailSize: String, Codable, CaseIterable, Sendable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case extraLarge = "Extra Large"

    var pixelSize: CGFloat {
        switch self {
        case .small: return 128
        case .medium: return 256
        case .large: return 384
        case .extraLarge: return 512
        }
    }
}
