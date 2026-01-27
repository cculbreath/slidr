import Foundation

enum VideoPlaybackMode: String, Codable, CaseIterable {
    case playFull
    case playOnce
    case limitDuration

    var displayName: String {
        switch self {
        case .playFull: return "Play Full Video"
        case .playOnce: return "Play Once"
        case .limitDuration: return "Limit to Slide Duration"
        }
    }

    var description: String {
        switch self {
        case .playFull:
            return "Plays the entire video before advancing to the next item"
        case .playOnce:
            return "Plays the video once, then advances even if video is shorter than slide duration"
        case .limitDuration:
            return "Plays video for the slideshow duration, then advances"
        }
    }
}
