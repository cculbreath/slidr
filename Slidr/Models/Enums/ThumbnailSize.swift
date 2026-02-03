import CoreGraphics

enum ThumbnailSize: String, Codable, CaseIterable, Sendable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    /// Logical point size used for SwiftUI layout (frame sizes, grid items).
    nonisolated var displaySize: CGFloat {
        switch self {
        case .small: return 128
        case .medium: return 256
        case .large: return 384
        }
    }

    /// Pixel dimensions for image generation — 2x displaySize for Retina sharpness.
    nonisolated var pixelSize: CGFloat {
        displaySize * 2
    }
}
