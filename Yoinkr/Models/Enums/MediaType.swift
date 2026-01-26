import Foundation

enum MediaType: String, Codable, CaseIterable, Sendable {
    case image
    case gif
    case video

    var defaultSlideshowDuration: TimeInterval {
        switch self {
        case .image: return 5.0
        case .gif: return 10.0
        case .video: return 0
        }
    }
}
