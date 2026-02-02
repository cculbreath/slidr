import Foundation
import OSLog

// MARK: - Data Types

struct TranscriptCue: Sendable {
    let index: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

struct SpeakerSegment: Sendable {
    let speaker: String?
    let text: String
}

enum TranscriptFormat: String, Sendable {
    case srt
    case vtt

    nonisolated init?(fileExtension: String) {
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

    nonisolated static func parse(fileAt url: URL) throws -> [TranscriptCue] {
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

    nonisolated static func extractPlainText(from cues: [TranscriptCue]) -> String {
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

    nonisolated private static func parseSRT(_ content: String) throws -> [TranscriptCue] {
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
    nonisolated private static func parseSRTTimestamp(_ string: String) -> TimeInterval? {
        // SRT uses comma for ms: 00:01:23,456
        let normalized = string.replacingOccurrences(of: ",", with: ".")
        return parseTimestamp(normalized)
    }

    // MARK: - VTT Parsing

    nonisolated private static func parseVTT(_ content: String) throws -> [TranscriptCue] {
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
    nonisolated private static func parseTimestamp(_ string: String) -> TimeInterval? {
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

    // MARK: - Speaker Segment Parsing

    /// Parses a cue's raw text into speaker-attributed segments.
    /// Handles VTT `<v SpeakerName>text</v>` voice tags and SRT `Speaker: text` prefixes.
    static func parseSpeakerSegments(_ rawText: String) -> [SpeakerSegment] {
        let lines = rawText.components(separatedBy: "\n")
        var segments: [SpeakerSegment] = []

        for line in lines {
            let lineSegments = parseLineSegments(line)
            segments.append(contentsOf: lineSegments)
        }

        if segments.isEmpty {
            let stripped = stripHTMLTags(rawText).trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty {
                return [SpeakerSegment(speaker: nil, text: stripped)]
            }
        }

        return segments
    }

    /// Returns ordered unique speaker names found across all cues.
    static func uniqueSpeakers(in cues: [TranscriptCue]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for cue in cues {
            for segment in parseSpeakerSegments(cue.text) {
                if let speaker = segment.speaker, !seen.contains(speaker) {
                    seen.insert(speaker)
                    ordered.append(speaker)
                }
            }
        }
        return ordered
    }

    private static func parseLineSegments(_ line: String) -> [SpeakerSegment] {
        // Try VTT voice tags first
        let voicePattern = #"<v(?:\.[^\s>]*)?\s+([^>]+)>(.*?)(?:</v>|$)"#
        if let regex = try? NSRegularExpression(pattern: voicePattern) {
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            if !matches.isEmpty {
                var segments: [SpeakerSegment] = []
                for match in matches {
                    guard let speakerRange = Range(match.range(at: 1), in: line),
                          let textRange = Range(match.range(at: 2), in: line) else { continue }
                    let speaker = String(line[speakerRange]).trimmingCharacters(in: .whitespaces)
                    let text = stripHTMLTags(String(line[textRange]))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        segments.append(SpeakerSegment(speaker: speaker, text: text))
                    }
                }
                return segments
            }
        }

        // Try SRT speaker prefix (e.g., "Alice: Hello")
        if let segment = parseSpeakerPrefix(line) {
            return [segment]
        }

        // Plain text — strip any remaining HTML tags
        let stripped = stripHTMLTags(line).trimmingCharacters(in: .whitespacesAndNewlines)
        if !stripped.isEmpty {
            return [SpeakerSegment(speaker: nil, text: stripped)]
        }

        return []
    }

    /// Parses `Speaker: text` prefix common in SRT files.
    /// Requires name to start with an uppercase letter to avoid false positives.
    private static func parseSpeakerPrefix(_ line: String) -> SpeakerSegment? {
        let pattern = #"^([A-Z][A-Za-z0-9 .'\-]{0,39}):\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        guard let speakerRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let speaker = String(line[speakerRange]).trimmingCharacters(in: .whitespaces)
        let text = String(line[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }
        return SpeakerSegment(speaker: speaker, text: text)
    }

    // MARK: - HTML Tag Stripping

    nonisolated private static func stripHTMLTags(_ string: String) -> String {
        string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
