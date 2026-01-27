import Foundation

enum UserFacingError: LocalizedError {
    case importFailed(count: Int, total: Int)
    case conversionFailed(filename: String)
    case playbackFailed(filename: String)
    case libraryCorrupted
    case insufficientSpace(required: Int64, available: Int64)
    case externalDriveNotMounted

    var errorDescription: String? {
        switch self {
        case .importFailed(let count, let total):
            return "Failed to import \(count) of \(total) files."
        case .conversionFailed(let filename):
            return "Failed to convert \"\(filename)\" to a compatible format."
        case .playbackFailed(let filename):
            return "Unable to play \"\(filename)\"."
        case .libraryCorrupted:
            return "The library database appears to be corrupted."
        case .insufficientSpace(let required, let available):
            let formatter = ByteCountFormatter()
            let req = formatter.string(fromByteCount: required)
            let avail = formatter.string(fromByteCount: available)
            return "Not enough disk space. \(req) required, \(avail) available."
        case .externalDriveNotMounted:
            return "The external drive is not currently mounted."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .importFailed:
            return "Check that the files are accessible and in a supported format."
        case .conversionFailed:
            return "The file may be in an unsupported codec. Try converting it manually."
        case .playbackFailed:
            return "The file may be corrupted or in an unsupported format."
        case .libraryCorrupted:
            return "Try restarting the app. If the problem persists, reset the library in Settings."
        case .insufficientSpace:
            return "Free up disk space or change the library location."
        case .externalDriveNotMounted:
            return "Connect the external drive and try again."
        }
    }
}
