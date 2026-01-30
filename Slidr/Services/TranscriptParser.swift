import Foundation
import OSLog

// MARK: - Data Types

struct TranscriptCue: Sendable {
    let index: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

enum TranscriptFormat: String, Sendable {
    case srt
    case vtt

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "srt": self = .srt
        case "vtt": self = .vtt
        default: return nil
        }
    }
}

enum TranscriptError: LocalizedError {
    case unsupportedFormat
    case parseFailure(String)
    case fileNotFound
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported transcript format. Only SRT and VTT files are supported."
        case .parseFailure(let detail):
            return "Failed to parse transcript: \(detail)"
        case .fileNotFound:
            return "Transcript file not found."
        case .emptyTranscript:
            return "Transcript file contains no cues."
        }
    }
}

// MARK: - Parser

struct TranscriptParser {

    static func parse(fileAt url: URL) throws -> [TranscriptCue] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TranscriptError.fileNotFound
        }

        guard let format = TranscriptFormat(fileExtension: url.pathExtension) else {
            throw TranscriptError.unsupportedFormat
        }

        let content = try String(contentsOf: url, encoding: .utf8)

        let cues: [TranscriptCue]
        switch format {
        case .srt:
            cues = try parseSRT(content)
        case .vtt:
            cues = try parseVTT(content)
        }

        guard !cues.isEmpty else {
            throw TranscriptError.emptyTranscript
        }

        return cues
    }

    static func extractPlainText(from cues: [TranscriptCue]) -> String {
        cues.map { stripHTMLTags($0.text) }.joined(separator: " ")
    }

    /// Binary search for the active cue at a given time.
    static func activeCue(at time: TimeInterval, in cues: [TranscriptCue]) -> TranscriptCue? {
        guard !cues.isEmpty else { return nil }

        var low = 0
        var high = cues.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let cue = cues[mid]

            if time < cue.startTime {
                high = mid - 1
            } else if time > cue.endTime {
                low = mid + 1
            } else {
                return cue
            }
        }

        return nil
    }

    // MARK: - SRT Parsing

    private static func parseSRT(_ content: String) throws -> [TranscriptCue] {
        let blocks = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var cues: [TranscriptCue] = []

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard lines.count >= 2 else { continue }

            // Find the timestamp line (contains " --> ")
            guard let timestampLineIndex = lines.firstIndex(where: { $0.contains(" --> ") }) else {
                continue
            }

            let timestampLine = lines[timestampLineIndex]
            let index = Int(lines[0]) ?? cues.count + 1
            let textLines = lines[(timestampLineIndex + 1)...]

            guard !textLines.isEmpty else { continue }

            let parts = timestampLine.components(separatedBy: " --> ")
            guard parts.count == 2,
                  let start = parseSRTTimestamp(parts[0].trimmingCharacters(in: .whitespaces)),
                  let end = parseSRTTimestamp(parts[1].trimmingCharacters(in: .whitespaces)) else {
                continue
            }

            let text = textLines.joined(separator: "\n")
            cues.append(TranscriptCue(index: index, startTime: start, endTime: end, text: text))
        }

        return cues
    }

    /// Parses SRT timestamp: `HH:MM:SS,mmm`
    private static func parseSRTTimestamp(_ string: String) -> TimeInterval? {
        // SRT uses comma for ms: 00:01:23,456
        let normalized = string.replacingOccurrences(of: ",", with: ".")
        return parseTimestamp(normalized)
    }

    // MARK: - VTT Parsing

    private static func parseVTT(_ content: String) throws -> [TranscriptCue] {
        var lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        // Verify WEBVTT header
        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              firstLine.hasPrefix("WEBVTT") else {
            throw TranscriptError.parseFailure("Missing WEBVTT header")
        }

        // Remove header
        lines.removeFirst()

        // Skip any header metadata (lines before first blank line after header)
        while let first = lines.first, !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeFirst()
        }

        // Rejoin and split by double newline to get blocks
        let remaining = lines.joined(separator: "\n")
        let blocks = remaining
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var cues: [TranscriptCue] = []
        var cueIndex = 1

        for block in blocks {
            let blockLines = block.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !blockLines.isEmpty else { continue }

            // Skip NOTE blocks
            if blockLines[0].hasPrefix("NOTE") { continue }
            // Skip STYLE blocks
            if blockLines[0].hasPrefix("STYLE") { continue }

            // Find timestamp line
            guard let timestampLineIndex = blockLines.firstIndex(where: { $0.contains(" --> ") }) else {
                continue
            }

            let timestampLine = blockLines[timestampLineIndex]
            let textLines = blockLines[(timestampLineIndex + 1)...]

            guard !textLines.isEmpty else { continue }

            // VTT timestamps can have position/alignment settings after the end time
            let arrowParts = timestampLine.components(separatedBy: " --> ")
            guard arrowParts.count == 2 else { continue }

            let startStr = arrowParts[0].trimmingCharacters(in: .whitespaces)
            // End time might have settings appended: "00:01:00.000 position:10%"
            let endAndSettings = arrowParts[1].trimmingCharacters(in: .whitespaces)
            let endStr = endAndSettings.components(separatedBy: " ").first ?? endAndSettings

            guard let start = parseTimestamp(startStr),
                  let end = parseTimestamp(endStr) else {
                continue
            }

            let text = textLines.joined(separator: "\n")
            cues.append(TranscriptCue(index: cueIndex, startTime: start, endTime: end, text: text))
            cueIndex += 1
        }

        return cues
    }

    // MARK: - Shared Timestamp Parsing

    /// Parses timestamps in `HH:MM:SS.mmm` or `MM:SS.mmm` format.
    private static func parseTimestamp(_ string: String) -> TimeInterval? {
        let components = string.components(separatedBy: ":")
        guard components.count >= 2 else { return nil }

        if components.count == 3 {
            // HH:MM:SS.mmm
            guard let hours = Double(components[0]),
                  let minutes = Double(components[1]),
                  let seconds = Double(components[2]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        } else {
            // MM:SS.mmm
            guard let minutes = Double(components[0]),
                  let seconds = Double(components[1]) else { return nil }
            return minutes * 60 + seconds
        }
    }

    // MARK: - HTML Tag Stripping

    private static func stripHTMLTags(_ string: String) -> String {
        string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
