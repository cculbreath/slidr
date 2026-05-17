import Foundation
import OSLog
import Vision

/// File-scoped logger so background work can use it without crossing the main actor.
private let duplicateDetectionLog = Logger(subsystem: "com.physicscloud.slidr", category: "Duplicates")

/// Mutable cancellation flag shared between the main actor and a detached task.
/// File-scoped and explicitly nonisolated so it isn't picked up by default-actor inference.
private final class DuplicateScanCancellationFlag: @unchecked Sendable {
    nonisolated(unsafe) var isCancelled: Bool = false
}

/// Finds visually-similar pairs of media items using cached Vision feature prints.
///
/// IMPLEMENTATION NOTE: This file is a stub — Agent B fills in the
/// implementations. The public surface here is the contract consumed by
/// `DuplicateScanCoordinator` and the duplicate review UI.
@MainActor
@Observable
final class DuplicateDetectionService {

    // MARK: - Public state

    private(set) var isScanning: Bool = false
    private(set) var progress: Double = 0
    private(set) var phase: String = ""
    private(set) var processedCount: Int = 0
    private(set) var totalCount: Int = 0

    /// Latest scan results. Cleared at the start of each scan.
    private(set) var pairs: [DuplicatePair] = []

    // MARK: - Tuning

    /// Maximum feature-print distance to flag as a duplicate.
    /// VNFeaturePrintObservation distances of 0.0 are identical; ~0.2 is
    /// effectively the same content; > 0.5 is unrelated. We compare via the
    /// best-of-frame-pairs minimum, so a slightly looser threshold still picks
    /// up re-encodes / re-uploads with high precision.
    var distanceThreshold: Float = 0.30

    /// For videos and GIFs (anything with a duration), require durations
    /// within this many seconds of each other before computing distance.
    /// Image pairs (no duration) skip this check.
    var durationToleranceSeconds: TimeInterval = 2.0

    // MARK: - Cancellation

    /// Set by `cancel()`; observed by background work. Reset at start of scan.
    private var cancellationFlag = DuplicateScanCancellationFlag()

    // MARK: - Public API

    /// Scan `items` for duplicate pairs. Populates `pairs`.
    /// - For items with a `duration` (videos AND GIFs), only compare items
    ///   within `durationToleranceSeconds` of each other.
    /// - For images (no duration), compare by mediaType + feature print only.
    /// - Skip items without `featurePrint` set.
    /// Honors cancellation. Updates progress/phase on main actor.
    func scan(items: [MediaItem]) async {
        // Reset state on the main actor.
        isScanning = true
        phase = "Scanning for duplicates"
        processedCount = 0
        totalCount = 0
        progress = 0
        pairs = []

        // Fresh cancellation flag for this scan.
        let flag = DuplicateScanCancellationFlag()
        cancellationFlag = flag

        defer {
            isScanning = false
            phase = ""
            pairs.sort { $0.distance < $1.distance }
        }

        // Filter to items with a feature print, and capture lightweight
        // value snapshots so the heavy work can happen off the main actor
        // without touching the @Model objects.
        struct Candidate: Sendable {
            let index: Int          // Index into the original items array.
            let mediaType: MediaType
            let duration: TimeInterval?
            /// Single-frame feature print. Always populated.
            let featurePrint: Data
            /// Per-keyframe feature prints for videos. Empty for images/gifs
            /// or videos that predate multi-frame fingerprinting.
            let featurePrintFrames: [Data]
        }

        var candidates: [Candidate] = []
        candidates.reserveCapacity(items.count)
        for (idx, item) in items.enumerated() {
            // Prefer multi-frame data; fall back to single-frame.
            let frames: [Data]
            if let framesData = item.featurePrintFrames,
               let decoded = try? JSONDecoder().decode([Data].self, from: framesData),
               !decoded.isEmpty {
                frames = decoded
            } else {
                frames = []
            }
            // Need at least one print to compare with.
            let single = item.featurePrint ?? frames.first
            guard let single else { continue }
            candidates.append(Candidate(
                index: idx,
                mediaType: item.mediaType,
                duration: item.duration,
                featurePrint: single,
                featurePrintFrames: frames
            ))
        }

        guard !candidates.isEmpty else {
            duplicateDetectionLog.info("Duplicate scan: no items with feature prints")
            return
        }

        let durationTolerance = self.durationToleranceSeconds
        let threshold = self.distanceThreshold

        // Run the heavy comparison work off the main actor.
        // Returns index-pair results so we can map back to MediaItem on the main actor.
        struct PairResult: Sendable {
            let indexA: Int
            let indexB: Int
            let distance: Float
        }

        // Numeric-only progress callback. Pairs are mapped to MediaItem on the
        // main actor after the detached task finishes — this avoids smuggling
        // the non-Sendable `[MediaItem]` array into a @Sendable closure.
        let progressHandler: @Sendable (Int, Int) -> Void = { processed, total in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.processedCount = processed
                self.totalCount = total
                self.progress = total > 0 ? Double(processed) / Double(total) : 0
            }
        }

        // Detached so we don't hold the main actor while doing the math.
        let results: [PairResult] = await Task.detached(priority: .userInitiated) { () -> [PairResult] in
            var foundPairs: [PairResult] = []

            // Group candidates by mediaType.
            var groups: [MediaType: [Candidate]] = [:]
            for c in candidates {
                groups[c.mediaType, default: []].append(c)
            }

            // Decode all feature prints up front so we don't pay the cost per comparison.
            // For videos with multi-frame data we keep an array of observations;
            // for everything else, a 1-element array containing the single print.
            // Index = candidate's original items[] index.
            var decoded: [Int: [VNFeaturePrintObservation]] = [:]
            decoded.reserveCapacity(candidates.count)
            for c in candidates {
                if flag.isCancelled { return foundPairs }
                if !c.featurePrintFrames.isEmpty {
                    let obs = c.featurePrintFrames.compactMap(FeaturePrintService.decode)
                    if !obs.isEmpty { decoded[c.index] = obs }
                } else if let obs = FeaturePrintService.decode(c.featurePrint) {
                    decoded[c.index] = [obs]
                }
            }

            // Helper: pairwise distance, returns nil on failure.
            func pairDistance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
                var out: Float = 0
                do {
                    try a.computeDistance(&out, to: b)
                    return out
                } catch {
                    duplicateDetectionLog.error("computeDistance failed: \(error.localizedDescription)")
                    return nil
                }
            }

            /// Minimum pairwise distance across all (frameA, frameB) combinations.
            /// Catches re-encodes whose thumbnail came from a different timestamp.
            func bestDistance(_ a: [VNFeaturePrintObservation], _ b: [VNFeaturePrintObservation]) -> Float? {
                var best: Float? = nil
                for fa in a {
                    for fb in b {
                        if let d = pairDistance(fa, fb) {
                            if best == nil || d < best! { best = d }
                        }
                    }
                }
                return best
            }

            // First pass: enumerate candidate pairs per group to compute totalCount.
            // We only count pairs where both feature prints decoded successfully.
            var totalPairs = 0
            for (mediaType, group) in groups {
                let decodedGroup = group.filter { decoded[$0.index] != nil }
                guard decodedGroup.count >= 2 else { continue }
                switch mediaType {
                case .video, .gif:
                    // Sliding window by duration. Items missing a duration are
                    // bucketed separately and compared all-vs-all defensively.
                    let withDuration = decodedGroup.filter { $0.duration != nil }
                        .sorted { ($0.duration ?? 0) < ($1.duration ?? 0) }
                    let withoutDuration = decodedGroup.filter { $0.duration == nil }
                    // Sliding window count.
                    var lo = 0
                    for hi in 0..<withDuration.count {
                        let hiDur = withDuration[hi].duration ?? 0
                        while lo < hi, (hiDur - (withDuration[lo].duration ?? 0)) > durationTolerance {
                            lo += 1
                        }
                        totalPairs += (hi - lo)
                    }
                    // All-vs-all for items without a duration (rare).
                    let n = withoutDuration.count
                    if n >= 2 {
                        totalPairs += (n * (n - 1)) / 2
                    }
                case .image:
                    let n = decodedGroup.count
                    totalPairs += (n * (n - 1)) / 2
                }
            }

            var processed = 0
            // Push initial totals to UI.
            progressHandler(0, totalPairs)

            // Throttle progress updates: flush every ~64 comparisons.
            let flushEvery = 64
            var sinceFlush = 0

            func considerPair(_ a: Candidate, _ b: Candidate) {
                guard let obsA = decoded[a.index], let obsB = decoded[b.index] else { return }
                if let d = bestDistance(obsA, obsB), d <= threshold {
                    foundPairs.append(PairResult(indexA: a.index, indexB: b.index, distance: d))
                }
                processed += 1
                sinceFlush += 1
                if sinceFlush >= flushEvery {
                    progressHandler(processed, totalPairs)
                    sinceFlush = 0
                }
            }

            // Second pass: actual comparisons.
            for (mediaType, group) in groups {
                if flag.isCancelled { break }
                let decodedGroup = group.filter { decoded[$0.index] != nil }
                guard decodedGroup.count >= 2 else { continue }

                switch mediaType {
                case .video, .gif:
                    let withDuration = decodedGroup.filter { $0.duration != nil }
                        .sorted { ($0.duration ?? 0) < ($1.duration ?? 0) }
                    let withoutDuration = decodedGroup.filter { $0.duration == nil }

                    // Two-pointer sweep over duration-sorted items.
                    var lo = 0
                    for hi in 0..<withDuration.count {
                        if flag.isCancelled { break }
                        let hiDur = withDuration[hi].duration ?? 0
                        while lo < hi, (hiDur - (withDuration[lo].duration ?? 0)) > durationTolerance {
                            lo += 1
                        }
                        for j in lo..<hi {
                            if flag.isCancelled { break }
                            considerPair(withDuration[j], withDuration[hi])
                        }
                    }

                    // Defensive all-vs-all for items lacking a duration.
                    if withoutDuration.count >= 2 {
                        for i in 0..<(withoutDuration.count - 1) {
                            if flag.isCancelled { break }
                            for j in (i + 1)..<withoutDuration.count {
                                if flag.isCancelled { break }
                                considerPair(withoutDuration[i], withoutDuration[j])
                            }
                        }
                    }

                case .image:
                    // All-vs-all within the image group.
                    let group = decodedGroup
                    for i in 0..<(group.count - 1) {
                        if flag.isCancelled { break }
                        for j in (i + 1)..<group.count {
                            if flag.isCancelled { break }
                            considerPair(group[i], group[j])
                        }
                    }
                }
            }

            // Final flush.
            progressHandler(processed, totalPairs)

            return foundPairs
        }.value

        // Map index pairs back to MediaItem references on the main actor.
        var newPairs: [DuplicatePair] = []
        newPairs.reserveCapacity(results.count)
        for r in results {
            guard r.indexA >= 0, r.indexA < items.count,
                  r.indexB >= 0, r.indexB < items.count else { continue }
            newPairs.append(DuplicatePair(
                itemA: items[r.indexA],
                itemB: items[r.indexB],
                distance: r.distance
            ))
        }
        self.pairs = newPairs

        // Final progress write so totals are exact even if cancellation interrupted.
        if self.totalCount > 0 {
            self.progress = min(1.0, Double(self.processedCount) / Double(self.totalCount))
        }

        if flag.isCancelled {
            duplicateDetectionLog.info("Duplicate scan cancelled after finding \(self.pairs.count) pair(s)")
        } else {
            duplicateDetectionLog.info("Duplicate scan complete: \(self.pairs.count) pair(s) within threshold \(self.distanceThreshold)")
        }
    }

    /// Cancel an in-flight scan.
    func cancel() {
        cancellationFlag.isCancelled = true
    }

    /// Remove a resolved pair from the in-memory results
    /// (called by the review UI after the user disposes of a pair).
    func remove(pair: DuplicatePair) {
        pairs.removeAll { $0.id == pair.id }
    }

    /// Remove every pair that references any of the given items.
    /// Use after deleting items so the UI can't try to render a tombstoned
    /// `@Model` reference that's still held by another pair.
    func removePairs(referencing items: [MediaItem]) {
        let trash = Set(items.map(\.id))
        pairs.removeAll { trash.contains($0.itemA.id) || trash.contains($0.itemB.id) }
    }
}
