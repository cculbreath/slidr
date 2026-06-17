import SwiftUI
import OSLog

struct DuplicatesView: View {
    @Bindable var coordinator: DuplicateScanCoordinator
    let library: MediaLibrary

    @State private var currentIndex: Int = 0
    @State private var hasScanned: Bool = false
    @State private var pendingDeleteBoth: Bool = false
    @FocusState private var keyboardFocused: Bool

    private var pairs: [DuplicatePair] { coordinator.detectionService.pairs }

    var body: some View {
        rootStack
            .modifier(DuplicatesKeyHandling(
                focused: $keyboardFocused,
                onLeft: { handleKeepLeft() },
                onRight: { handleKeepRight() },
                onSkip: { handleSkip() },
                onKeepBoth: { handleKeepBoth() },
                onDeleteBoth: { requestDeleteBoth() }
            ))
            .alert("Delete both items?", isPresented: $pendingDeleteBoth) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Both", role: .destructive) { handleDeleteBoth() }
            } message: {
                Text("Both files will be moved to the Trash. You can restore them from Trash if needed.")
            }
            .onChange(of: pairs.count) { _, newCount in
                if currentIndex >= newCount { currentIndex = max(0, newCount - 1) }
            }
    }

    private var rootStack: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Duplicates")
                    .font(.title)
                    .fontWeight(.semibold)
                if coordinator.isRunning {
                    ProgressView(value: coordinator.overallProgress)
                        .frame(maxWidth: 320)
                    Text(coordinator.phaseLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !pairs.isEmpty {
                    Text("\(pairs.count) candidate pair\(pairs.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            headerActions
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var headerActions: some View {
        if coordinator.isRunning {
            Button(role: .destructive) {
                coordinator.cancel()
                Logger.duplicates.info("User cancelled in-flight scan")
            } label: {
                Label("Cancel", systemImage: "stop.circle")
            }
            .controlSize(.large)
        } else {
            HStack(spacing: 8) {
                Button {
                    startScan(force: false)
                } label: {
                    Label("Scan for Duplicates", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Menu {
                    Button("Re-scan (force recompute feature prints)") {
                        startScan(force: true)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if coordinator.isRunning && pairs.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text(coordinator.phaseLabel)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if pairs.isEmpty && !hasScanned {
            EmptyStateView(
                title: "No scan yet",
                subtitle: "Press Scan for Duplicates to find visually-similar items.",
                systemImage: "rectangle.on.rectangle.angled",
                action: { startScan(force: false) },
                actionLabel: "Scan for Duplicates"
            )
        } else if pairs.isEmpty {
            VStack(spacing: 12) {
                Text("No duplicates found")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Your library looks clean.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            pairReview
        }
    }

    // MARK: - Pair Review

    private var pairReview: some View {
        let safeIndex = min(max(currentIndex, 0), pairs.count - 1)
        let pair = pairs[safeIndex]
        return VStack(spacing: 12) {
            HStack {
                Text("Pair \(safeIndex + 1) of \(pairs.count)")
                    .font(.headline)
                Spacer()
                Text(String(format: "distance %.3f", pair.distance))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            HStack(alignment: .top, spacing: 16) {
                DuplicatePairCardView(
                    snapshot: pair.snapshotA,
                    label: "Left",
                    keepShortcutHint: "\u{2190}",
                    onKeep: handleKeepLeft
                )
                DuplicatePairCardView(
                    snapshot: pair.snapshotB,
                    label: "Right",
                    keepShortcutHint: "\u{2192}",
                    onKeep: handleKeepRight
                )
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
            bottomToolbar
        }
        .id(pair.id)
    }

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            Button {
                handleSkip()
            } label: {
                Label("Skip", systemImage: "arrow.right.circle")
            }
            .keyboardShortcut(.space, modifiers: [])

            Button {
                handleKeepBoth()
            } label: {
                Label("Keep Both", systemImage: "checkmark.circle")
            }

            Button(role: .destructive) {
                requestDeleteBoth()
            } label: {
                Label("Delete Both", systemImage: "trash")
            }

            Spacer()

            Text("\u{2190} keep left  \u{00b7}  \u{2192} keep right  \u{00b7}  Space skip  \u{00b7}  B keep both  \u{00b7}  D delete both")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Actions

    private enum PairAction { case keepLeft, keepRight, keepBoth, deleteBoth }

    private func startScan(force: Bool) {
        Task {
            Logger.duplicates.info("Starting duplicate scan (force=\(force))")
            await coordinator.runFullScan(items: library.allItems, force: force)
            await MainActor.run {
                hasScanned = true
                currentIndex = 0
                keyboardFocused = true
            }
        }
    }

    private func handleKeepLeft()  { apply(.keepLeft) }
    private func handleKeepRight() { apply(.keepRight) }
    private func handleKeepBoth()  { apply(.keepBoth) }
    private func handleDeleteBoth() { apply(.deleteBoth) }

    private func handleSkip() {
        guard !pairs.isEmpty else { return }
        let next = currentIndex + 1
        currentIndex = next >= pairs.count ? 0 : next
    }

    private func requestDeleteBoth() {
        guard currentPair() != nil else { return }
        pendingDeleteBoth = true
    }

    private func apply(_ action: PairAction) {
        guard let pair = currentPair() else { return }
        // Remove pairs from the review list BEFORE delete() lands so SwiftUI
        // can't render a tombstoned @Model reference.
        switch action {
        case .keepLeft:
            Logger.duplicates.info("Keep \(pair.snapshotA.filename, privacy: .public); trash \(pair.snapshotB.filename, privacy: .public)")
            coordinator.detectionService.removePairs(referencing: [pair.members[1]])
            _ = pair.delete(side: .right, in: library)
        case .keepRight:
            Logger.duplicates.info("Keep \(pair.snapshotB.filename, privacy: .public); trash \(pair.snapshotA.filename, privacy: .public)")
            coordinator.detectionService.removePairs(referencing: [pair.members[0]])
            _ = pair.delete(side: .left, in: library)
        case .keepBoth:
            Logger.duplicates.info("Keep both in pair (\(pair.snapshotA.filename, privacy: .public), \(pair.snapshotB.filename, privacy: .public))")
            coordinator.detectionService.remove(pair: pair)
        case .deleteBoth:
            Logger.duplicates.info("Trash both in pair (\(pair.snapshotA.filename, privacy: .public), \(pair.snapshotB.filename, privacy: .public))")
            coordinator.detectionService.removePairs(referencing: pair.members)
            pair.deleteBoth(in: library)
        }
        advanceAfterRemoval()
    }

    private func currentPair() -> DuplicatePair? {
        guard !pairs.isEmpty else { return nil }
        let safeIndex = min(max(currentIndex, 0), pairs.count - 1)
        return pairs[safeIndex]
    }

    private func advanceAfterRemoval() {
        // After remove(pair:) the array shrinks; clamp index so we stay on the
        // pair that slid into our slot (effectively "next").
        if currentIndex >= pairs.count {
            currentIndex = max(0, pairs.count - 1)
        }
    }
}

private struct DuplicatesKeyHandling: ViewModifier {
    @FocusState.Binding var focused: Bool
    let onLeft: () -> Void
    let onRight: () -> Void
    let onSkip: () -> Void
    let onKeepBoth: () -> Void
    let onDeleteBoth: () -> Void

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onKeyPress(.leftArrow) { onLeft(); return .handled }
            .onKeyPress(.rightArrow) { onRight(); return .handled }
            .onKeyPress(.space) { onSkip(); return .handled }
            .onKeyPress(.init("b")) { onKeepBoth(); return .handled }
            .onKeyPress(.init("d")) { onDeleteBoth(); return .handled }
    }
}
