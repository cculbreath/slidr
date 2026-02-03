import AVFoundation
import Foundation
import OSLog

actor WhisperTranscriptionService {
    private static let logger = Logger(subsystem: "com.physicscloud.slidr", category: "Transcription")
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    static let maxFileSize: Int = 100 * 1024 * 1024 // 100 MB Groq dev tier limit

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    struct TranscriptionResult: Sendable {
        let text: String
    }

    // MARK: - Transcribe

    func transcribe(audioURL: URL, model: String, apiKey: String) async throws -> TranscriptionResult {
        let fileData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent

        if fileData.count > Self.maxFileSize {
            let fileSizeMB = fileData.count / 1_048_576
            let limitMB = Self.maxFileSize / 1_048_576
            Self.logger.warning("Audio file \(filename) is \(fileSizeMB)MB, exceeds Groq \(limitMB)MB limit")
            throw TranscriptionError.fileTooLarge(sizeMB: fileSizeMB, limitMB: limitMB)
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType(for: audioURL))\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"model\"\r\n\r\n".utf8))
        body.append(Data("\(model)\r\n".utf8))
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".utf8))
        body.append(Data("text\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))

        request.httpBody = body

        Self.logger.info("Transcribing \(filename) (\(fileData.count / 1_048_576)MB) with model \(model)")

        let (data, response) = try await session.data(for: request)

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
        // Prefer ffmpeg (handles more containers reliably), fall back to AVFoundation
        if let ffmpegPath = await FFmpegHelper.findFFmpeg() {
            return try await extractAudioWithFFmpeg(from: videoURL, ffmpegPath: ffmpegPath)
        }
        Self.logger.info("ffmpeg not found, using AVFoundation for audio extraction")
        return try await extractAudioWithAVFoundation(from: videoURL)
    }

    private func extractAudioWithFFmpeg(from videoURL: URL, ffmpegPath: String) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".m4a")

        Self.logger.info("Extracting audio with ffmpeg: \(videoURL.lastPathComponent)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-i", videoURL.path,
            "-vn",              // No video
            "-acodec", "aac",   // AAC codec
            "-b:a", "128k",     // 128k bitrate (keeps file size reasonable)
            "-ar", "16000",     // 16kHz (optimal for speech recognition)
            "-ac", "1",         // Mono
            "-y",               // Overwrite
            outputURL.path
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    Self.logger.info("ffmpeg audio extraction complete: \(outputURL.lastPathComponent)")
                    continuation.resume(returning: outputURL)
                } else {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "unknown error"
                    Self.logger.error("ffmpeg failed (exit \(proc.terminationStatus)): \(errorOutput.suffix(200))")
                    try? FileManager.default.removeItem(at: outputURL)
                    continuation.resume(throwing: TranscriptionError.exportFailed(
                        NSError(domain: "FFmpeg", code: Int(proc.terminationStatus),
                                userInfo: [NSLocalizedDescriptionKey: "ffmpeg audio extraction failed: \(errorOutput.suffix(200))"])
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: TranscriptionError.exportFailed(error))
            }
        }
    }

    private func extractAudioWithAVFoundation(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw TranscriptionError.noAudioTrack
        }
        _ = audioTrack

        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".m4a")

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.exportSessionFailed
        }

        do {
            try await exportSession.export(to: outputURL, as: .m4a)
        } catch {
            throw TranscriptionError.exportFailed(error)
        }

        Self.logger.info("AVFoundation audio extracted to \(outputURL.lastPathComponent)")
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
    case fileTooLarge(sizeMB: Int, limitMB: Int)

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
        case .fileTooLarge(let sizeMB, let limitMB):
            return "Audio file too large (\(sizeMB)MB). Groq limit is \(limitMB)MB."
        }
    }
}

