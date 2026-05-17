import Foundation
import OSLog

/// Orchestrates a duplicate scan: first computes feature prints for any
/// items missing them, then runs `DuplicateDetectionService` to find pairs.
/// UI binds to the two underlying services for progress display.
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

    /// Overall progress 0...1 across both phases, weighted 70% compute / 30% scan.
    var overallProgress: Double {
        if featurePrintService.isComputing {
            return featurePrintService.progress * 0.7
        }
        if detectionService.isScanning {
            return 0.7 + detectionService.progress * 0.3
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
