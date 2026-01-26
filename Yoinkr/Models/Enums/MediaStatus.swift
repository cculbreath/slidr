import Foundation

enum MediaStatus: String, Codable, Sendable {
    case available
    case missing
    case externalNotMounted
    case corrupted
}
