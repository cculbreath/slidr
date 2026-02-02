import AVFoundation
import Foundation
import OSLog

actor WhisperTranscriptionService {
    private static let logger = Logger(subsystem: "com.physicscloud.slidr", category: "Transcription")
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!

    struct TranscriptionResult: Sendable {
        let text: String
    }

    // MARK: - Transcribe

    func transcribe(audioURL: URL, model: String, apiKey: String) async throws -> TranscriptionResult {
        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent

        var body = Data()
        body.appendMultipart(boundary: boundary, name: "file", filename: filename, mimeType: mimeType(for: audioURL), data: audioData)
        body.appendMultipart(boundary: boundary, name: "model", value: model)
        body.appendMultipart(boundary: boundary, name: "response_format", value: "text")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        Self.logger.info("Transcribing \(filename) with model \(model)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "unknown"
            Self.logger.error("Transcription failed (\(httpResponse.statusCode)): \(responseBody)")
            throw TranscriptionError.apiError(statusCode: httpResponse.statusCode, body: responseBody)
        }

        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Self.logger.info("Transcription complete: \(text.prefix(100))...")

        return TranscriptionResult(text: text)
    }

    // MARK: - Audio Extraction

    func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw TranscriptionError.noAudioTrack
        }
        _ = audioTrack // Verify audio track exists

        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".m4a")

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.exportSessionFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        guard exportSession.status == .completed else {
            if let error = exportSession.error {
                throw TranscriptionError.exportFailed(error)
            }
            throw TranscriptionError.exportSessionFailed
        }

        Self.logger.info("Audio extracted to \(outputURL.lastPathComponent)")
        return outputURL
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

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case noAudioTrack
    case exportSessionFailed
    case exportFailed(Error)
    case invalidResponse
    case apiError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "Video has no audio track"
        case .exportSessionFailed:
            return "Failed to create audio export session"
        case .exportFailed(let error):
            return "Audio extraction failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from transcription API"
        case .apiError(let statusCode, let body):
            return "Transcription API error (\(statusCode)): \(body)"
        }
    }
}

// MARK: - Data Multipart Helper

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
