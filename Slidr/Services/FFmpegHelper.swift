import AppKit
import Foundation
import OSLog

enum FFmpegHelper {
    private static let logger = Logger(subsystem: "com.physicscloud.slidr", category: "FFmpeg")

    // MARK: - Tool Discovery

    static func findFFmpeg() -> String? {
        findTool("ffmpeg")
    }

    static func findFFprobe() -> String? {
        findTool("ffprobe")
    }

    private static func findTool(_ name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Synchronous `which` is acceptable here — runs once at discovery time, <1ms
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                return path
            }
        }
        return nil
    }

    // MARK: - Async Process Runner

    private static func runProcess(executablePath: String, arguments: [String], stdoutPipe: Pipe? = nil) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe ?? FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
    }

    // MARK: - Duration

    static func videoDuration(url: URL) async -> Double? {
        guard let ffprobe = findFFprobe() else {
            logger.warning("ffprobe not found, cannot get duration for \(url.lastPathComponent)")
            return nil
        }

        let pipe = Pipe()
        let status = await runProcess(
            executablePath: ffprobe,
            arguments: [
                "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                url.path,
            ],
            stdoutPipe: pipe
        )

        guard status == 0 else {
            logger.warning("ffprobe exited with status \(status) for \(url.lastPathComponent)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let duration = Double(output) else {
            return nil
        }

        logger.info("ffprobe duration for \(url.lastPathComponent): \(duration)s")
        return duration
    }

    // MARK: - Single Frame Extraction

    static func extractFrame(from url: URL, atSeconds: Double, maxSize: CGFloat) async -> NSImage? {
        guard let ffmpeg = findFFmpeg() else { return nil }

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let status = await runProcess(
            executablePath: ffmpeg,
            arguments: [
                "-ss", String(format: "%.3f", atSeconds),
                "-i", url.path,
                "-frames:v", "1",
                "-vf", "scale=\(Int(maxSize)):\(Int(maxSize)):force_original_aspect_ratio=decrease",
                "-q:v", "2",
                "-y",
                outputURL.path,
            ]
        )

        guard status == 0 else { return nil }
        return NSImage(contentsOf: outputURL)
    }

    // MARK: - Multi-Frame Extraction

    static func extractFrames(from url: URL, count: Int, thumbnailSize: CGFloat) async -> [NSImage] {
        guard let duration = await videoDuration(url: url), duration > 0 else { return [] }
        guard let ffmpeg = findFFmpeg() else { return [] }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var frames: [NSImage] = []

        for i in 0..<count {
            let fraction = Double(i) / Double(max(count - 1, 1))
            let time = fraction * duration
            let outputURL = tempDir.appendingPathComponent("frame_\(i).jpg")

            let status = await runProcess(
                executablePath: ffmpeg,
                arguments: [
                    "-ss", String(format: "%.3f", time),
                    "-i", url.path,
                    "-frames:v", "1",
                    "-vf", "scale=\(Int(thumbnailSize)):\(Int(thumbnailSize)):force_original_aspect_ratio=decrease",
                    "-q:v", "2",
                    "-y",
                    outputURL.path,
                ]
            )

            if status == 0, let image = NSImage(contentsOf: outputURL) {
                frames.append(image)
            }
        }

        logger.info("ffmpeg extracted \(frames.count)/\(count) frames from \(url.lastPathComponent)")
        return frames
    }

    static func extractFrameRange(from url: URL, startFraction: Double, endFraction: Double, count: Int, thumbSize: CGFloat) async -> [NSImage] {
        guard let duration = await videoDuration(url: url), duration > 0 else { return [] }
        guard let ffmpeg = findFFmpeg() else { return [] }

        let startTime = startFraction * duration
        let endTime = endFraction * duration

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var frames: [NSImage] = []

        for i in 0..<count {
            let fraction = Double(i) / Double(max(count - 1, 1))
            let time = startTime + fraction * (endTime - startTime)
            let outputURL = tempDir.appendingPathComponent("frame_\(i).jpg")

            let status = await runProcess(
                executablePath: ffmpeg,
                arguments: [
                    "-ss", String(format: "%.3f", time),
                    "-i", url.path,
                    "-frames:v", "1",
                    "-vf", "scale=\(Int(thumbSize)):\(Int(thumbSize)):force_original_aspect_ratio=decrease",
                    "-q:v", "2",
                    "-y",
                    outputURL.path,
                ]
            )

            if status == 0, let image = NSImage(contentsOf: outputURL) {
                frames.append(image)
            }
        }

        return frames
    }
}
