import Foundation
import Vision
import AppKit
import AVFoundation
import OSLog
import SwiftData

/// Computes and caches Vision feature prints for media items.
/// - Images: a single feature print of the thumbnail, stored in `MediaItem.featurePrint`.
/// - Videos: a 5-frame fingerprint sampled evenly across the duration, JSON-encoded as
///   `[Data]` in `MediaItem.featurePrintFrames`. Used by `DuplicateDetectionService` to
///   compute the minimum pairwise distance across all frame combinations — catches
///   re-encodes whose static thumbnail was taken from a different timestamp.
/// - GIFs: single feature print of the thumbnail (treated like images).
@MainActor
@Observable
final class FeaturePrintService {

    // MARK: - Public state (observed by progress UI)

    /// True while a compute pass is running.
    private(set) var isComputing: Bool = false
    /// 0.0 ... 1.0 progress for the current pass.
    private(set) var progress: Double = 0
    /// Human-readable phase label for the progress overlay.
    private(set) var phase: String = ""
    /// Number of items processed in the current pass.
    private(set) var processedCount: Int = 0
    /// Total items to process in the current pass.
    private(set) var totalCount: Int = 0

    // MARK: - Tuning

    /// Number of keyframes to sample for video feature prints.
    static let videoFrameSampleCount = 5

    // MARK: - Dependencies

    private weak var library: MediaLibrary?
    private var isCancelled: Bool = false

    private static let log = Logger(subsystem: "com.physicscloud.slidr", category: "FeaturePrint")

    init(library: MediaLibrary? = nil) {
        self.library = library
    }

    func configure(library: MediaLibrary) {
        self.library = library
    }

    // MARK: - Public API

    /// Compute and store the feature print(s) for a single item.
    /// For videos, populates `featurePrintFrames` (the multi-keyframe fingerprint).
    /// For images and gifs, populates `featurePrint` from the thumbnail.
    func compute(for item: MediaItem) async throws {
        guard let library else { return }

        if item.mediaType == .video {
            let url = library.absoluteURL(for: item)
            let duration = item.duration ?? 0
            let frames = try await Self.generateVideoFrameFeaturePrints(
                url: url,
                duration: duration,
                sampleCount: Self.videoFrameSampleCount
            )
            if !frames.isEmpty {
                item.featurePrintFrames = try JSONEncoder().encode(frames)
            }
            // Also fill in the single-frame featurePrint (using the middle frame)
            // so any code that still consults the single print has something useful.
            if let middle = frames[safe: frames.count / 2] {
                item.featurePrint = middle
            }
        } else {
            let image = try await library.thumbnail(for: item, size: .medium)
            var rect = CGRect(origin: .zero, size: image.size)
            guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                return
            }
            if let data = try await Self.generateFeaturePrintData(cgImage: cgImage) {
                item.featurePrint = data
            }
        }
    }

    /// Iterate `items`, compute and persist feature prints for those that
    /// don't yet have one. Honors cancellation.
    func computeAll(in items: [MediaItem], force: Bool = false) async {
        let targets: [MediaItem]
        if force {
            targets = items
        } else {
            targets = items.filter { item in
                if item.mediaType == .video {
                    return item.featurePrintFrames == nil
                } else {
                    return item.featurePrint == nil
                }
            }
        }

        isCancelled = false
        isComputing = true
        phase = "Computing feature prints"
        processedCount = 0
        totalCount = targets.count
        progress = 0

        defer {
            isComputing = false
            phase = ""
        }

        for item in targets {
            if isCancelled { break }
            do {
                try await compute(for: item)
            } catch {
                Self.log.error("Failed to compute feature print for \(item.originalFilename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            processedCount += 1
            progress = Double(processedCount) / Double(max(totalCount, 1))
        }

        if let context = library?.modelContainer.mainContext {
            do {
                try context.save()
            } catch {
                Self.log.error("Failed to save feature prints: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Cancel any in-flight pass.
    func cancel() {
        isCancelled = true
    }

    // MARK: - Vision

    private nonisolated static func generateFeaturePrintData(cgImage: CGImage) async throws -> Data? {
        try await Task.detached(priority: .userInitiated) {
            return try featurePrintData(for: cgImage)
        }.value
    }

    /// Synchronous helper for use inside an already-detached task.
    private nonisolated static func featurePrintData(for cgImage: CGImage) throws -> Data? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            return nil
        }
        return try NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
    }

    /// Pull `sampleCount` evenly-spaced frames from the video and feature-print each.
    private nonisolated static func generateVideoFrameFeaturePrints(
        url: URL,
        duration: TimeInterval,
        sampleCount: Int
    ) async throws -> [Data] {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let assetDuration = duration > 0 ? duration : CMTimeGetSeconds(try await asset.load(.duration))
            guard assetDuration.isFinite, assetDuration > 0 else { return [] }

            // Sample at 10%, 30%, 50%, 70%, 90% of duration (avoids title cards / end cards).
            let fractions: [Double] = (0..<sampleCount).map { i in
                (Double(i) + 0.5) / Double(sampleCount)
            }
            let times = fractions.map { CMTime(seconds: assetDuration * $0, preferredTimescale: 600) }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            // Modest size — VNGenerateImageFeaturePrintRequest scales internally,
            // but smaller input keeps decode fast.
            generator.maximumSize = CGSize(width: 480, height: 480)

            var prints: [Data] = []
            prints.reserveCapacity(times.count)
            for time in times {
                do {
                    let cgImage = try await generator.image(at: time).image
                    if let data = try? featurePrintData(for: cgImage) {
                        prints.append(data)
                    }
                } catch {
                    // Skip frames that fail (DRM-protected, seek-past-end, etc.).
                    Self.log.debug("Frame extract failed at \(CMTimeGetSeconds(time))s for \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return prints
        }.value
    }

    // MARK: - Decode helpers

    /// Reconstruct a VNFeaturePrintObservation from stored single-frame data.
    nonisolated static func decode(_ data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    /// Reconstruct an array of VNFeaturePrintObservations from multi-frame data.
    nonisolated static func decodeFrames(_ data: Data) -> [VNFeaturePrintObservation] {
        guard let array = try? JSONDecoder().decode([Data].self, from: data) else { return [] }
        return array.compactMap(decode)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
