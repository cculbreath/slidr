import Foundation

enum SortOrder: String, Codable, CaseIterable, Sendable {
    case name = "Name"
    case dateModified = "Date Modified"
    case dateImported = "Date Imported"
    case fileSize = "File Size"
    case duration = "Duration"
}
