import CoreGraphics

enum ThumbnailSize: String, Codable, CaseIterable, Sendable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    /// Pixel dimensions for thumbnail generation.
    /// Values are 2x the logical point size to stay sharp on Retina displays.
    nonisolated var pixelSize: CGFloat {
        switch self {
        case .small: return 256
        case .medium: return 512
        case .large: return 768
        }
    }
}
