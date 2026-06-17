import Foundation
import OSLog

/// Orchestrates a duplicate scan: first compute feature prints for items
/// missing them, then run pair detection. UI binds to the two underlying
/// services for progress display.
@MainActor
@Observable
final class DuplicateScanCoordinator {
    let featurePrintService: FeaturePrintService
    let detectionService: DuplicateDetectionService
    private weak var library: MediaLibrary?

    init() {
        self.featurePrintService = FeaturePrintService()
        self.detectionService = DuplicateDetectionService()
    }

    func configure(library: MediaLibrary) {
        self.library = library
        featurePrintService.configure(library: library)
    }

    var isRunning: Bool {
        featurePrintService.isComputing || detectionService.isScanning
    }

    /// Overall progress 0...1 across both phases. Feature-print compute dominates
    /// wall-time on first scans, so it gets the larger share.
    private static let computeShare: Double = 0.7
    private static let scanShare: Double = 1 - computeShare

    var overallProgress: Double {
        if featurePrintService.isComputing {
            return featurePrintService.progress * Self.computeShare
        }
        if detectionService.isScanning {
            return Self.computeShare + detectionService.progress * Self.scanShare
        }
        return 0
    }

    var phaseLabel: String {
        if featurePrintService.isComputing { return featurePrintService.phase }
        if detectionService.isScanning { return detectionService.phase }
        return ""
    }

    /// Run a full pass: compute any missing feature prints, then detect duplicates.
    /// `force` re-computes all feature prints even if already cached.
    func runFullScan(items: [MediaItem], force: Bool = false) async {
        await featurePrintService.computeAll(in: items, force: force)
        await detectionService.scan(items: items)
    }

    func cancel() {
        featurePrintService.cancel()
        detectionService.cancel()
    }
}
