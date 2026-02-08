import Foundation
import OSLog

actor MistralTranscriptionService {
    private static let logger = Logger(subsystem: "com.physicscloud.slidr", category: "Transcription")
    private let endpoint = URL(string: "https://api.mistral.ai/v1/audio/transcriptions")!
    static let maxFileSize: Int = 100 * 1024 * 1024 // 100 MB

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    // MARK: - Response Types

    private struct MistralResponse: Decodable {
        let text: String
        let segments: [Segment]?

        struct Segment: Decodable {
            let start: Double
            let end: Double
            let text: String
            let speakerId: String?

            enum CodingKeys: String, CodingKey {
                case start, end, text
                case speakerId = "speaker_id"
            }
        }
    }

    // MARK: - Transcribe

    func transcribe(audioURL: URL, model: String, apiKey: String) async throws -> TranscriptionResult {
        let fileData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent

        if fileData.count > Self.maxFileSize {
            let fileSizeMB = fileData.count / 1_048_576
            let limitMB = Self.maxFileSize / 1_048_576
            Self.logger.warning("Audio file \(filename) is \(fileSizeMB)MB, exceeds \(limitMB)MB limit")
            throw TranscriptionError.fileTooLarge(sizeMB: fileSizeMB, limitMB: limitMB)
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // File field
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType(for: audioURL))\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n".utf8))
        // Model field
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"model\"\r\n\r\n".utf8))
        body.append(Data("\(model)\r\n".utf8))
        // Timestamp granularities field
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"timestamp_granularities\"\r\n\r\n".utf8))
        body.append(Data("segment\r\n".utf8))
        // Close boundary
        body.append(Data("--\(boundary)--\r\n".utf8))

        request.httpBody = body

        Self.logger.info("Transcribing \(filename) (\(fileData.count / 1_048_576)MB) with Mistral model \(model)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "unknown"
            Self.logger.error("Mistral transcription failed (\(httpResponse.statusCode)): \(responseBody)")
            throw TranscriptionError.apiError(statusCode: httpResponse.statusCode, body: responseBody)
        }

        let decoded = try JSONDecoder().decode(MistralResponse.self, from: data)
        let srtContent = Self.segmentsToSRT(decoded.segments ?? [])
        let plainText = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)

        Self.logger.info("Mistral transcription complete (\(decoded.segments?.count ?? 0) segments): \(plainText.prefix(100))...")

        return TranscriptionResult(text: plainText, srtContent: srtContent)
    }

    // MARK: - SRT Conversion

    private static func segmentsToSRT(_ segments: [MistralResponse.Segment]) -> String {
        var lines: [String] = []
        for (index, segment) in segments.enumerated() {
            lines.append("\(index + 1)")
            lines.append("\(formatSRTTimestamp(segment.start)) --> \(formatSRTTimestamp(segment.end))")
            lines.append(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatSRTTimestamp(_ seconds: Double) -> String {
        let totalMs = Int(seconds * 1000)
        let ms = totalMs % 1000
        let s = (totalMs / 1000) % 60
        let m = (totalMs / 60000) % 60
        let h = totalMs / 3600000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    // MARK: - Helpers

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "mp4": return "video/mp4"
        case "webm": return "audio/webm"
        case "ogg": return "audio/ogg"
        default: return "application/octet-stream"
        }
    }
}
