import Foundation

struct VerificationResult {
    let totalItems: Int
    let verifiedItems: Int
    let missingItems: Int
    let orphanedThumbnails: Int
    let duration: TimeInterval

    var allValid: Bool {
        missingItems == 0
    }

    var summary: String {
        var parts: [String] = []
        parts.append("\(verifiedItems)/\(totalItems) files verified")
        if missingItems > 0 {
            parts.append("\(missingItems) missing")
        }
        if orphanedThumbnails > 0 {
            parts.append("\(orphanedThumbnails) orphaned thumbnails")
        }
        return parts.joined(separator: ", ")
    }
}
