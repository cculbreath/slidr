import Foundation

/// Display mode for slideshow captions.
enum CaptionDisplayMode: String, Codable, CaseIterable {
    case overlay
    case outside

    var displayName: String {
        switch self {
        case .overlay: return "Overlay on Media"
        case .outside: return "Outside Media"
        }
    }
}
