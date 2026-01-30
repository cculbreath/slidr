import SwiftUI

struct GridKeyboardModifier: ViewModifier {
    let viewModel: GridViewModel
    let onDelete: () -> Void
    let onQuickLook: () -> Void
    let onStartSlideshow: () -> Void
    let onRevealInFinder: () -> Void
    let onToggleFilenames: () -> Void
    let onToggleCaptions: () -> Void
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let onMoveSelection: (NavigationDirection) -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(.delete) {
                onDelete()
                return .handled
            }
            .onKeyPress(.upArrow) {
                onMoveSelection(.up)
                return .handled
            }
            .onKeyPress(.downArrow) {
                onMoveSelection(.down)
                return .handled
            }
            .onKeyPress(.leftArrow) {
                onMoveSelection(.left)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                onMoveSelection(.right)
                return .handled
            }
            .onKeyPress(.space) {
                onQuickLook()
                return .handled
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectAll)) { _ in
                onSelectAll()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deselectAll)) { _ in
                onDeselectAll()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deleteSelected)) { _ in
                onDelete()
            }
            .onReceive(NotificationCenter.default.publisher(for: .increaseThumbnailSize)) { _ in
                viewModel.increaseThumbnailSize()
            }
            .onReceive(NotificationCenter.default.publisher(for: .decreaseThumbnailSize)) { _ in
                viewModel.decreaseThumbnailSize()
            }
            .onReceive(NotificationCenter.default.publisher(for: .startSlideshow)) { _ in
                onStartSlideshow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetThumbnailSize)) { _ in
                viewModel.resetThumbnailSize()
            }
            .onReceive(NotificationCenter.default.publisher(for: .revealInFinder)) { _ in
                onRevealInFinder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleGridFilenames)) { _ in
                onToggleFilenames()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleGridCaptions)) { _ in
                onToggleCaptions()
            }
    }
}

extension View {
    func gridKeyboardHandling(
        viewModel: GridViewModel,
        onDelete: @escaping () -> Void,
        onQuickLook: @escaping () -> Void,
        onStartSlideshow: @escaping () -> Void,
        onRevealInFinder: @escaping () -> Void,
        onToggleFilenames: @escaping () -> Void,
        onToggleCaptions: @escaping () -> Void,
        onSelectAll: @escaping () -> Void,
        onDeselectAll: @escaping () -> Void,
        onMoveSelection: @escaping (NavigationDirection) -> Void
    ) -> some View {
        modifier(GridKeyboardModifier(
            viewModel: viewModel,
            onDelete: onDelete,
            onQuickLook: onQuickLook,
            onStartSlideshow: onStartSlideshow,
            onRevealInFinder: onRevealInFinder,
            onToggleFilenames: onToggleFilenames,
            onToggleCaptions: onToggleCaptions,
            onSelectAll: onSelectAll,
            onDeselectAll: onDeselectAll,
            onMoveSelection: onMoveSelection
        ))
    }
}
