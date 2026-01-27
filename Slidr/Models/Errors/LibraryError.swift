import Foundation

enum LibraryError: LocalizedError {
    case sourceFileNotFound
    case destinationAlreadyExists
    case copyFailed(underlying: Error)
    case migrationFailed(underlying: Error)
    case invalidLibraryPath
    case databaseSaveFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .sourceFileNotFound:
            return "The source file could not be found."
        case .destinationAlreadyExists:
            return "A file already exists at the destination."
        case .copyFailed(let error):
            return "Failed to copy file: \(error.localizedDescription)"
        case .migrationFailed(let error):
            return "Library migration failed: \(error.localizedDescription)"
        case .invalidLibraryPath:
            return "The specified library path is invalid."
        case .databaseSaveFailed(let error):
            return "Failed to save to database: \(error.localizedDescription)"
        }
    }
}
