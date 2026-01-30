import Foundation

/// Shared formatters for consistent, efficient formatting across the app.
/// Formatters are expensive to create, so we cache them as static properties.
enum Formatters {

    // MARK: - Date Formatters

    /// Standard date formatter: "Jan 15, 2024 at 3:45 PM"
    static let mediumDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Date only: "January 15, 2024"
    static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    /// Short date: "1/15/24"
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    // MARK: - Number Formatters

    /// File size formatter: "4.5 MB", "1.2 GB"
    static let fileSize: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    // MARK: - Convenience Methods

    /// Format a date with medium date and short time style
    static func formatDate(_ date: Date) -> String {
        mediumDateTime.string(from: date)
    }

    /// Format a file size in bytes
    static func formatFileSize(_ bytes: Int64) -> String {
        fileSize.string(fromByteCount: bytes)
    }
}
