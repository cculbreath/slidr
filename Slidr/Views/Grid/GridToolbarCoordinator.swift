import AppKit
import SwiftUI

// MARK: - ResilientToolbar

/// NSToolbar subclass that catches unbalanced KVO observer removal.
/// SwiftUI's BarAppearanceBridge may try to remove a "displayMode" observer
/// it never registered, causing an NSRangeException. This subclass silently
/// absorbs that failure.
class ResilientToolbar: NSToolbar {
    override func removeObserver(_ observer: NSObject, forKeyPath keyPath: String) {
        do {
            try ObjCExceptionCatcher.catchException {
                super.removeObserver(observer, forKeyPath: keyPath)
            }
        } catch {
            // Silently absorb unbalanced KVO removal
        }
    }

    override func removeObserver(_ observer: NSObject, forKeyPath keyPath: String, context: UnsafeMutableRawPointer?) {
        do {
            try ObjCExceptionCatcher.catchException {
                super.removeObserver(observer, forKeyPath: keyPath, context: context)
            }
        } catch {
            // Silently absorb unbalanced KVO removal
        }
    }
}

// MARK: - Toolbar Item Identifiers

/// Toolbar identifiers in a nonisolated enum to avoid MainActor isolation issues with NSToolbarDelegate.
@MainActor
enum ToolbarID {
    nonisolated static let slideshow = NSToolbarItem.Identifier("slideshow")
    nonisolated static let importFiles = NSToolbarItem.Identifier("import")
    nonisolated static let thumbnailSize = NSToolbarItem.Identifier("thumbnailSize")
    nonisolated static let captionVisibility = NSToolbarItem.Identifier("captionVisibility")
    nonisolated static let hoverScrub = NSToolbarItem.Identifier("hoverScrub")
    nonisolated static let gifAnimation = NSToolbarItem.Identifier("gifAnimation")
    nonisolated static let playbackOptions = NSToolbarItem.Identifier("playbackOptions")
    nonisolated static let mediaTypeFilter = NSToolbarItem.Identifier("mediaTypeFilter")
    nonisolated static let productionFilter = NSToolbarItem.Identifier("productionFilter")
    nonisolated static let tagFilter = NSToolbarItem.Identifier("tagFilter")
    nonisolated static let subtitleFilter = NSToolbarItem.Identifier("subtitleFilter")
    nonisolated static let advancedFilter = NSToolbarItem.Identifier("advancedFilter")
    nonisolated static let sortOrder = NSToolbarItem.Identifier("sortOrder")
    nonisolated static let inspectorToggle = NSToolbarItem.Identifier("inspector")
    nonisolated static let sidebarSeparator = NSToolbarItem.Identifier("sidebarSeparator")
    nonisolated static let inspectorSeparator = NSToolbarItem.Identifier("inspectorSeparator")
    nonisolated static let tagPalette = NSToolbarItem.Identifier("tagPalette")
    nonisolated static let viewMode = NSToolbarItem.Identifier("viewMode")
}

// MARK: - GridToolbarCoordinator

@MainActor
@Observable
final class GridToolbarCoordinator: NSObject, NSToolbarDelegate {
    // MARK: - Dependencies
    weak var viewModel: GridViewModel?
    weak var settings: AppSettings?
    var itemsEmpty: Bool = true
    var allTags: [String] = []

    // MARK: - Action callbacks
    var onStartSlideshow: (() -> Void)?
    var onImport: (() -> Void)?
    var onToggleGIFAnimation: (() -> Void)?
    var onToggleHoverScrub: (() -> Void)?
    var onToggleCaptions: (() -> Void)?
    var onToggleFilenames: (() -> Void)?
    var onToggleInspector: (() -> Void)?
    var onShowAdvancedFilter: (() -> Void)?
    var onViewModeChanged: ((BrowserViewMode) -> Void)?

    // MARK: - Tag Palette
    let tagPaletteViewModel = TagPaletteViewModel()

    @ObservationIgnored
    private(set) lazy var tagPaletteController = TagPaletteWindowController(viewModel: tagPaletteViewModel)

    // MARK: - Toolbar
    let toolbar: NSToolbar

    // MARK: - Item cache for state updates
    @ObservationIgnored
    private var itemCache: [NSToolbarItem.Identifier: NSToolbarItem] = [:]

    // MARK: - Split view reference for tracking separators
    @ObservationIgnored
    var splitView: NSSplitView?

    // MARK: - Observation token
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

    // MARK: - Init

    override init() {
        // Bump identifier to avoid loading stale SwiftUI toolbar config
        let tb = ResilientToolbar(identifier: "gridToolbar.v2")
        tb.allowsUserCustomization = true
        tb.autosavesConfiguration = true
        tb.displayMode = .iconOnly
        self.toolbar = tb
        super.init()
        tb.delegate = self
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Observation

    func startObserving() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                withObservationTracking {
                    self.readObservedState()
                } onChange: {
                    Task { @MainActor [weak self] in
                        self?.updateItemStates()
                    }
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Touch all observable properties we want to track.
    private func readObservedState() {
        guard let vm = viewModel else { return }
        _ = vm.thumbnailSize
        _ = vm.mediaTypeFilter
        _ = vm.productionTypeFilter
        _ = vm.tagFilter
        _ = vm.subtitleFilter
        _ = vm.advancedFilter
        _ = vm.sortOrder
        _ = vm.sortAscending
        _ = settings?.animateGIFsInGrid
        _ = settings?.gridVideoHoverScrub
        _ = settings?.gridShowCaptions
        _ = settings?.gridShowFilenames
        _ = vm.browserMode
        _ = itemsEmpty
    }

    // MARK: - NSToolbarDelegate

    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            ToolbarID.sidebarSeparator,
            ToolbarID.viewMode,
            ToolbarID.slideshow,
            ToolbarID.importFiles,
            ToolbarID.thumbnailSize,
            ToolbarID.captionVisibility,
            ToolbarID.hoverScrub,
            ToolbarID.gifAnimation,
            ToolbarID.mediaTypeFilter,
            .flexibleSpace,
            ToolbarID.productionFilter,
            ToolbarID.tagFilter,
            ToolbarID.advancedFilter,
            ToolbarID.sortOrder,
            ToolbarID.inspectorSeparator,
            ToolbarID.inspectorToggle,
        ]
    }

    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            ToolbarID.sidebarSeparator,
            ToolbarID.viewMode,
            ToolbarID.slideshow,
            ToolbarID.importFiles,
            ToolbarID.thumbnailSize,
            ToolbarID.captionVisibility,
            ToolbarID.hoverScrub,
            ToolbarID.gifAnimation,
            ToolbarID.playbackOptions,
            ToolbarID.mediaTypeFilter,
            ToolbarID.productionFilter,
            ToolbarID.tagFilter,
            ToolbarID.tagPalette,
            ToolbarID.subtitleFilter,
            ToolbarID.advancedFilter,
            ToolbarID.sortOrder,
            ToolbarID.inspectorSeparator,
            ToolbarID.inspectorToggle,
            .flexibleSpace,
            .space,
        ]
    }

    nonisolated func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        MainActor.assumeIsolated {
            let item = makeItem(for: itemIdentifier)
            if let item {
                itemCache[itemIdentifier] = item
            }
            return item
        }
    }

    // MARK: - Item Factory

    private func makeItem(for identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch identifier {
        case ToolbarID.viewMode:
            return makeViewModeItem()
        case ToolbarID.slideshow:
            return makeSlideshowItem()
        case ToolbarID.importFiles:
            return makeImportItem()
        case ToolbarID.thumbnailSize:
            return makeThumbnailSizeItem()
        case ToolbarID.captionVisibility:
            return makeCaptionVisibilityItem()
        case ToolbarID.hoverScrub:
            return makeHoverScrubItem()
        case ToolbarID.gifAnimation:
            return makeGIFAnimationItem()
        case ToolbarID.playbackOptions:
            return makePlaybackOptionsGroup()
        case ToolbarID.mediaTypeFilter:
            return makeMediaTypeFilterItem()
        case ToolbarID.productionFilter:
            return makeProductionFilterItem()
        case ToolbarID.tagFilter:
            return makeTagFilterItem()
        case ToolbarID.tagPalette:
            return makeTagPaletteItem()
        case ToolbarID.subtitleFilter:
            return makeSubtitleFilterItem()
        case ToolbarID.advancedFilter:
            return makeAdvancedFilterItem()
        case ToolbarID.sortOrder:
            return makeSortOrderItem()
        case ToolbarID.inspectorToggle:
            return makeInspectorItem()
        case ToolbarID.sidebarSeparator:
            return makeSidebarSeparator()
        case ToolbarID.inspectorSeparator:
            return makeInspectorSeparator()
        default:
            return nil
        }
    }

    // MARK: - View Mode

    private func makeViewModeItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarID.viewMode)
        item.label = "View"
        item.paletteLabel = "View Mode"
        item.toolTip = "Switch between grid and list view"

        let seg = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Grid")!,
                NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "List")!,
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(viewModeAction(_:))
        )
        seg.segmentStyle = .separated
        let mode = viewModel?.browserMode ?? .grid
        seg.selectedSegment = mode == .grid ? 0 : 1
        seg.setWidth(36, forSegment: 0)
        seg.setWidth(36, forSegment: 1)
        item.view = seg
        return item
    }

    // MARK: - Button Items

    private func makeSlideshowItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarID.slideshow)
        item.label = "Slideshow"
        item.paletteLabel = "Slideshow"
        item.toolTip = "Start Slideshow"
        item.isBordered = true
        item.isEnabled = !itemsEmpty

        let button = NSButton(image: NSImage(systemSymbolName: "play.rectangle.on.rectangle", accessibilityDescription: "Slideshow")!, target: self, action: #selector(slideshowAction))
        button.bezelStyle = .toolbar
        item.view = button
        return item
    }

    private func makeImportItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarID.importFiles)
        item.label = "Import"
        item.paletteLabel = "Import"
        item.toolTip = "Import Files"
        item.isBordered = true

        let button = NSButton(image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Import")!, target: self, action: #selector(importAction))
        button.bezelStyle = .toolbar
        item.view = button
        return item
    }

    private func makeThumbnailSizeItem() -> NSToolbarItem {
        let group = NSToolbarItemGroup(itemIdentifier: ToolbarID.thumbnailSize)
        group.label = "Thumbnail Size"
        group.paletteLabel = "Thumbnail Size"

        let segmented = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Large")!,
                NSImage(systemSymbolName: "square.grid.3x2", accessibilityDescription: "Medium")!,
                NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "Small")!,
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(thumbnailSizeAction(_:))
        )

        let currentSize = viewModel?.thumbnailSize ?? .medium
        switch currentSize {
        case .large: segmented.selectedSegment = 0
        case .medium: segmented.selectedSegment = 1
        case .small: segmented.selectedSegment = 2
        }

        segmented.segmentStyle = .separated
        segmented.controlSize = .regular

        group.view = segmented
        return group
    }

    private func makeCaptionVisibilityItem() -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: ToolbarID.captionVisibility)
        item.label = "Captions"
        item.paletteLabel = "Captions"
        item.toolTip = "Caption Visibility"
        item.image = captionVisibilityImage()
        item.menu = buildCaptionMenu()
        return item
    }

    private func makeHoverScrubItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarID.hoverScrub)
        item.label = "Scrubbing"
        item.paletteLabel = "Scrubbing"
        item.toolTip = "Toggle video scrub on hover"
        item.isBordered = true

        let enabled = settings?.gridVideoHoverScrub ?? false
        let button = NSButton(image: hoverScrubImage(enabled: enabled), target: self, action: #selector(hoverScrubAction))
        button.bezelStyle = .toolbar
        button.contentTintColor = enabled ? .controlAccentColor : nil
        item.view = button
        return item
    }

    private func makeGIFAnimationItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarID.gifAnimation)
        item.label = "Autoplay GIFs"
        item.paletteLabel = "Autoplay GIFs"
        item.toolTip = "Toggle GIF animation in grid"
        item.isBordered = true

        let enabled = settings?.animateGIFsInGrid ?? false
        let button = NSButton(image: gifAnimationImage(enabled: enabled), target: self, action: #selector(gifAnimationAction))
        button.bezelStyle = .toolbar
        button.contentTintColor = enabled ? .controlAccentColor : nil
        item.view = button
        return item
    }

    private func makePlaybackOptionsGroup() -> NSToolbarItem {
        let group = NSToolbarItemGroup(itemIdentifier: ToolbarID.playbackOptions)
        group.label = "Playback Options"
        group.paletteLabel = "Playback Options"

        let scrubEnabled = settings?.gridVideoHoverScrub ?? false
        let gifEnabled = settings?.animateGIFsInGrid ?? false

        let segmented = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "hand.point.up.braille", accessibilityDescription: "Scrubbing")!,
                NSImage(systemSymbolName: "waveform.path.ecg.rectangle", accessibilityDescription: "Autoplay GIFs")!,
            ],
            trackingMode: .momentary,
            target: self,
            action: #selector(playbackOptionsAction(_:))
        )
        segmented.segmentStyle = .separated
        segmented.controlSize = .regular

        // Tint active segments
        if scrubEnabled {
            segmented.setImage(
                NSImage(systemSymbolName: "hand.point.up.braille", accessibilityDescription: "Scrubbing")!
                    .withSymbolConfiguration(.init(paletteColors: [.controlAccentColor]))!,
                forSegment: 0
            )
        }
        if gifEnabled {
            segmented.setImage(
                NSImage(systemSymbolName: "waveform.path.ecg.rectangle", accessibilityDescription: "Autoplay GIFs")!
                    .withSymbolConfiguration(.init(paletteColors: [.controlAccentColor]))!,
                forSegment: 1
            )
        }

        group.view = segmented
        return group
    }

    private func makeSubtitleFilterItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarID.subtitleFilter)
        item.label = "Has Transcript"
        item.paletteLabel = "Has Transcript"
        item.toolTip = "Show only items with transcripts"
        item.isBordered = true

        let active = viewModel?.subtitleFilter ?? false
        let button = NSButton(image: subtitleFilterImage(active: active), target: self, action: #selector(subtitleFilterAction))
        button.bezelStyle = .toolbar
        button.contentTintColor = active ? .controlAccentColor : nil
        item.view = button
        return item
    }

    private func makeAdvancedFilterItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarID.advancedFilter)
        item.label = "Advanced Filter"
        item.paletteLabel = "Advanced Filter"
        item.toolTip = "Open advanced filter"
        item.isBordered = true

        let active = viewModel?.advancedFilter != nil
        let button = NSButton(image: advancedFilterImage(active: active), target: self, action: #selector(advancedFilterAction))
        button.bezelStyle = .toolbar
        button.contentTintColor = active ? .controlAccentColor : nil
        item.view = button
        return item
    }

    private func makeInspectorItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarID.inspectorToggle)
        item.label = "Inspector"
        item.paletteLabel = "Inspector"
        item.toolTip = "Toggle Inspector"
        item.isBordered = true

        let button = NSButton(image: NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Inspector")!, target: self, action: #selector(inspectorAction))
        button.bezelStyle = .toolbar
        item.view = button
        return item
    }

    // MARK: - Menu Items

    private func makeMediaTypeFilterItem() -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: ToolbarID.mediaTypeFilter)
        item.label = "Media Types"
        item.paletteLabel = "Media Types"
        item.toolTip = "Filter by media type"

        let hasFilter = !(viewModel?.mediaTypeFilter.isEmpty ?? true)
        item.image = NSImage(systemSymbolName: "square.stack.3d.forward.dottedline", accessibilityDescription: "Media Types")!
            .withSymbolConfiguration(.init(paletteColors: hasFilter ? [.controlAccentColor] : [.labelColor]))

        item.menu = buildMediaTypeMenu()
        return item
    }

    private func makeProductionFilterItem() -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: ToolbarID.productionFilter)
        item.label = "Production"
        item.paletteLabel = "Production"
        item.toolTip = "Filter by production type"

        let hasFilter = !(viewModel?.productionTypeFilter.isEmpty ?? true)
        item.image = NSImage(systemSymbolName: "film", accessibilityDescription: "Production")!
            .withSymbolConfiguration(.init(paletteColors: hasFilter ? [.controlAccentColor] : [.labelColor]))

        item.menu = buildProductionTypeMenu()
        return item
    }

    private func makeTagFilterItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarID.tagFilter)
        item.label = "Tags"
        item.paletteLabel = "Tags"
        item.toolTip = "Filter by tags"

        let hasFilter = !(viewModel?.tagFilter.isEmpty ?? true)
        let image = tagFilterComposedImage(hasFilter: hasFilter)

        let button = NSButton(image: image, target: self, action: #selector(tagFilterAction(_:)))
        button.bezelStyle = .toolbar
        button.isBordered = true
        item.view = button
        return item
    }

    private func tagFilterComposedImage(hasFilter: Bool) -> NSImage {
        let tint: NSColor = hasFilter ? .controlAccentColor : .labelColor
        let tagSymbol = hasFilter ? "tag.fill" : "tag"
        let tagImage = NSImage(systemSymbolName: tagSymbol, accessibilityDescription: "Tags")!
            .withSymbolConfiguration(.init(paletteColors: [tint]))!

        let chevronConfig = NSImage.SymbolConfiguration(pointSize: 6, weight: .bold)
        let chevronImage = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)!
            .withSymbolConfiguration(chevronConfig.applying(.init(paletteColors: [tint])))!

        let tagSize = tagImage.size
        let chevronSize = chevronImage.size
        let spacing: CGFloat = 2
        let totalWidth = tagSize.width + spacing + chevronSize.width
        let totalHeight = max(tagSize.height, chevronSize.height)

        let composed = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { rect in
            let tagY = (rect.height - tagSize.height) / 2
            tagImage.draw(in: NSRect(x: 0, y: tagY, width: tagSize.width, height: tagSize.height))

            let chevronX = tagSize.width + spacing
            let chevronY = (rect.height - chevronSize.height) / 2
            chevronImage.draw(in: NSRect(x: chevronX, y: chevronY, width: chevronSize.width, height: chevronSize.height))
            return true
        }
        composed.isTemplate = false
        return composed
    }

    private func makeTagPaletteItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: ToolbarID.tagPalette)
        item.label = "Tag Palette"
        item.paletteLabel = "Tag Palette"
        item.toolTip = "Toggle floating tag palette"

        let visible = tagPaletteController.isVisible
        let symbolName = visible ? "tag.square.fill" : "tag.square"
        let button = NSButton(
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: "Tag Palette")!,
            target: self,
            action: #selector(tagPaletteAction)
        )
        button.bezelStyle = .toolbar
        button.contentTintColor = visible ? .controlAccentColor : nil
        item.view = button
        return item
    }

    private func makeSortOrderItem() -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: ToolbarID.sortOrder)
        item.label = "Sort"
        item.paletteLabel = "Sort"
        item.toolTip = "Sort order"
        item.image = NSImage(systemSymbolName: "arrow.up.arrow.down.circle", accessibilityDescription: "Sort")!
        item.menu = buildSortMenu()
        return item
    }

    // MARK: - Tracking Separators

    private func makeSidebarSeparator() -> NSToolbarItem {
        guard let splitView else {
            let item = NSToolbarItem(itemIdentifier: ToolbarID.sidebarSeparator)
            item.label = ""
            item.paletteLabel = "Sidebar Separator"
            return item
        }
        return NSTrackingSeparatorToolbarItem(identifier: ToolbarID.sidebarSeparator, splitView: splitView, dividerIndex: 0)
    }

    private func makeInspectorSeparator() -> NSToolbarItem {
        guard let splitView, splitView.arrangedSubviews.count > 2 else {
            let item = NSToolbarItem(itemIdentifier: ToolbarID.inspectorSeparator)
            item.label = ""
            item.paletteLabel = "Inspector Separator"
            return item
        }
        return NSTrackingSeparatorToolbarItem(identifier: ToolbarID.inspectorSeparator, splitView: splitView, dividerIndex: 1)
    }

    // MARK: - State Updates

    func updateItemStates() {
        guard let vm = viewModel else { return }

        // View mode
        if let item = itemCache[ToolbarID.viewMode], let seg = item.view as? NSSegmentedControl {
            seg.selectedSegment = vm.browserMode == .grid ? 0 : 1
        }

        // Slideshow enabled state
        if let item = itemCache[ToolbarID.slideshow] {
            item.isEnabled = !itemsEmpty
            if let button = item.view as? NSButton {
                button.isEnabled = !itemsEmpty
            }
        }

        // Thumbnail size
        if let item = itemCache[ToolbarID.thumbnailSize], let seg = item.view as? NSSegmentedControl {
            switch vm.thumbnailSize {
            case .large: seg.selectedSegment = 0
            case .medium: seg.selectedSegment = 1
            case .small: seg.selectedSegment = 2
            }
        }

        // Hover scrub toggle
        if let item = itemCache[ToolbarID.hoverScrub], let button = item.view as? NSButton {
            let enabled = settings?.gridVideoHoverScrub ?? false
            button.image = hoverScrubImage(enabled: enabled)
            button.contentTintColor = enabled ? .controlAccentColor : nil
        }

        // GIF animation toggle
        if let item = itemCache[ToolbarID.gifAnimation], let button = item.view as? NSButton {
            let enabled = settings?.animateGIFsInGrid ?? false
            button.image = gifAnimationImage(enabled: enabled)
            button.contentTintColor = enabled ? .controlAccentColor : nil
        }

        // Playback options group
        if let item = itemCache[ToolbarID.playbackOptions], let seg = item.view as? NSSegmentedControl {
            let scrubEnabled = settings?.gridVideoHoverScrub ?? false
            let gifEnabled = settings?.animateGIFsInGrid ?? false
            seg.setImage(
                NSImage(systemSymbolName: "hand.point.up.braille", accessibilityDescription: "Scrubbing")!
                    .withSymbolConfiguration(.init(paletteColors: scrubEnabled ? [.controlAccentColor] : [.labelColor]))!,
                forSegment: 0
            )
            seg.setImage(
                NSImage(systemSymbolName: "waveform.path.ecg.rectangle", accessibilityDescription: "Autoplay GIFs")!
                    .withSymbolConfiguration(.init(paletteColors: gifEnabled ? [.controlAccentColor] : [.labelColor]))!,
                forSegment: 1
            )
        }

        // Caption visibility
        if let item = itemCache[ToolbarID.captionVisibility] as? NSMenuToolbarItem {
            item.image = captionVisibilityImage()
            item.menu = buildCaptionMenu()
        }

        // Media type filter
        if let item = itemCache[ToolbarID.mediaTypeFilter] as? NSMenuToolbarItem {
            let hasFilter = !vm.mediaTypeFilter.isEmpty
            item.image = NSImage(systemSymbolName: "square.stack.3d.forward.dottedline", accessibilityDescription: "Media Types")!
                .withSymbolConfiguration(.init(paletteColors: hasFilter ? [.controlAccentColor] : [.labelColor]))
            item.menu = buildMediaTypeMenu()
        }

        // Production type filter
        if let item = itemCache[ToolbarID.productionFilter] as? NSMenuToolbarItem {
            let hasFilter = !vm.productionTypeFilter.isEmpty
            item.image = NSImage(systemSymbolName: "film", accessibilityDescription: "Production")!
                .withSymbolConfiguration(.init(paletteColors: hasFilter ? [.controlAccentColor] : [.labelColor]))
            item.menu = buildProductionTypeMenu()
        }

        // Tag filter
        if let item = itemCache[ToolbarID.tagFilter], let button = item.view as? NSButton {
            let hasFilter = !vm.tagFilter.isEmpty
            button.image = tagFilterComposedImage(hasFilter: hasFilter)
        }

        // Subtitle filter
        if let item = itemCache[ToolbarID.subtitleFilter], let button = item.view as? NSButton {
            let active = vm.subtitleFilter
            button.image = subtitleFilterImage(active: active)
            button.contentTintColor = active ? .controlAccentColor : nil
        }

        // Advanced filter
        if let item = itemCache[ToolbarID.advancedFilter], let button = item.view as? NSButton {
            let active = vm.advancedFilter != nil
            button.image = advancedFilterImage(active: active)
            button.contentTintColor = active ? .controlAccentColor : nil
        }

        // Sort order
        if let item = itemCache[ToolbarID.sortOrder] as? NSMenuToolbarItem {
            item.menu = buildSortMenu()
        }

        // Tag palette button highlight
        if let item = itemCache[ToolbarID.tagPalette], let button = item.view as? NSButton {
            let visible = tagPaletteController.isVisible
            let symbolName = visible ? "tag.square.fill" : "tag.square"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Tag Palette")!
            button.contentTintColor = visible ? .controlAccentColor : nil
        }
    }

    // MARK: - Tag Palette

    func configurePalette() {
        tagPaletteViewModel.allTags = allTags
        tagPaletteViewModel.tagFilter = viewModel?.tagFilter ?? []
        tagPaletteViewModel.onTagFilterChanged = { [weak self] newFilter in
            self?.viewModel?.tagFilter = newFilter
            self?.updateItemStates()
        }
        tagPaletteViewModel.onShowAdvancedFilter = { [weak self] in
            self?.onShowAdvancedFilter?()
        }
    }

    func updatePaletteTagCounts(_ counts: [String: Int]) {
        tagPaletteViewModel.tagCounts = counts
    }

    func updatePaletteSelectedItems(_ items: [MediaItem]) {
        tagPaletteViewModel.selectedItems = items
    }

    func toggleTagPalette() {
        tagPaletteController.toggle()
        updateItemStates()
    }

    func syncPaletteTagFilter() {
        tagPaletteViewModel.tagFilter = viewModel?.tagFilter ?? []
    }

    // MARK: - Image Helpers

    private func captionVisibilityImage() -> NSImage {
        let captionsOn = (settings?.gridShowCaptions ?? true) || (settings?.gridShowFilenames ?? false)
        let symbolName = captionsOn ? "eye.fill" : "eye"
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: "Captions")!
            .withSymbolConfiguration(.init(paletteColors: captionsOn ? [.controlAccentColor] : [.labelColor]))!
    }

    private func hoverScrubImage(enabled: Bool) -> NSImage {
        NSImage(systemSymbolName: "hand.point.up.braille", accessibilityDescription: "Scrubbing")!
    }

    private func gifAnimationImage(enabled: Bool) -> NSImage {
        NSImage(systemSymbolName: "waveform.path.ecg.rectangle", accessibilityDescription: "Autoplay GIFs")!
    }

    private func subtitleFilterImage(active: Bool) -> NSImage {
        NSImage(systemSymbolName: active ? "captions.bubble.fill" : "captions.bubble", accessibilityDescription: "Has Transcript")!
    }

    private func advancedFilterImage(active: Bool) -> NSImage {
        NSImage(systemSymbolName: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle", accessibilityDescription: "Advanced Filter")!
    }

    // MARK: - Menu Builders

    private func buildCaptionMenu() -> NSMenu {
        let menu = NSMenu()

        let captionItem = NSMenuItem(title: "Caption", action: #selector(toggleCaptionsAction), keyEquivalent: "")
        captionItem.target = self
        captionItem.state = (settings?.gridShowCaptions ?? true) ? .on : .off
        menu.addItem(captionItem)

        let filenameItem = NSMenuItem(title: "Filename", action: #selector(toggleFilenamesAction), keyEquivalent: "")
        filenameItem.target = self
        filenameItem.state = (settings?.gridShowFilenames ?? false) ? .on : .off
        menu.addItem(filenameItem)

        return menu
    }

    private func buildMediaTypeMenu() -> NSMenu {
        let menu = NSMenu()
        let filter = viewModel?.mediaTypeFilter ?? []

        let allItem = NSMenuItem(title: "All", action: #selector(mediaTypeAllAction), keyEquivalent: "")
        allItem.target = self
        allItem.state = filter.isEmpty ? .on : .off
        menu.addItem(allItem)

        menu.addItem(.separator())

        for type in MediaType.allCases {
            let menuItem = NSMenuItem(title: type.rawValue.capitalized, action: #selector(mediaTypeToggleAction(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = type.rawValue
            menuItem.state = filter.contains(type) ? .on : .off
            menu.addItem(menuItem)
        }

        return menu
    }

    private func buildProductionTypeMenu() -> NSMenu {
        let menu = NSMenu()
        let filter = viewModel?.productionTypeFilter ?? []

        let allItem = NSMenuItem(title: "All", action: #selector(productionTypeAllAction), keyEquivalent: "")
        allItem.target = self
        allItem.state = filter.isEmpty ? .on : .off
        menu.addItem(allItem)

        menu.addItem(.separator())

        for type in ProductionType.allCases {
            let menuItem = NSMenuItem(title: type.displayName, action: #selector(productionTypeToggleAction(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = type.rawValue
            menuItem.image = NSImage(systemSymbolName: type.iconName, accessibilityDescription: type.displayName)
            menuItem.state = filter.contains(type) ? .on : .off
            menu.addItem(menuItem)
        }

        return menu
    }

    private func buildSortMenu() -> NSMenu {
        let menu = NSMenu()
        let currentSort = viewModel?.sortOrder ?? .dateImported
        let ascending = viewModel?.sortAscending ?? false

        for order in SortOrder.allCases {
            let menuItem = NSMenuItem(title: order.rawValue, action: #selector(sortOrderAction(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = order.rawValue
            menuItem.state = currentSort == order ? .on : .off
            menu.addItem(menuItem)
        }

        menu.addItem(.separator())

        let ascItem = NSMenuItem(title: "Ascending", action: #selector(sortAscendingAction(_:)), keyEquivalent: "")
        ascItem.target = self
        ascItem.state = ascending ? .on : .off
        menu.addItem(ascItem)

        return menu
    }

    // MARK: - Actions

    @objc private func viewModeAction(_ sender: NSSegmentedControl) {
        let mode: BrowserViewMode = sender.selectedSegment == 0 ? .grid : .list
        viewModel?.browserMode = mode
        onViewModeChanged?(mode)
    }

    @objc private func slideshowAction() {
        onStartSlideshow?()
    }

    @objc private func importAction() {
        onImport?()
    }

    @objc private func thumbnailSizeAction(_ sender: NSSegmentedControl) {
        guard let vm = viewModel else { return }
        switch sender.selectedSegment {
        case 0: vm.thumbnailSize = .large
        case 1: vm.thumbnailSize = .medium
        case 2: vm.thumbnailSize = .small
        default: break
        }
    }

    @objc private func toggleCaptionsAction() {
        onToggleCaptions?()
        updateItemStates()
    }

    @objc private func toggleFilenamesAction() {
        onToggleFilenames?()
        updateItemStates()
    }

    @objc private func hoverScrubAction() {
        onToggleHoverScrub?()
        updateItemStates()
    }

    @objc private func gifAnimationAction() {
        onToggleGIFAnimation?()
        updateItemStates()
    }

    @objc private func playbackOptionsAction(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: onToggleHoverScrub?()
        case 1: onToggleGIFAnimation?()
        default: break
        }
        updateItemStates()
    }

    @objc private func subtitleFilterAction() {
        viewModel?.subtitleFilter.toggle()
        updateItemStates()
    }

    @objc private func advancedFilterAction() {
        onShowAdvancedFilter?()
    }

    @objc private func inspectorAction() {
        onToggleInspector?()
    }

    @objc private func tagPaletteAction() {
        toggleTagPalette()
    }

    @objc private func tagFilterAction(_ sender: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 240, height: 360)

        guard let vm = viewModel else { return }
        let tagBinding = Binding<Set<String>>(
            get: { vm.tagFilter },
            set: { vm.tagFilter = $0 }
        )
        let hasFilter = !vm.tagFilter.isEmpty
        let content = TagFilterPopover(allTags: allTags, tagFilter: tagBinding, hasTagFilter: hasFilter, tagCounts: tagPaletteViewModel.tagCounts)
        popover.contentViewController = NSHostingController(rootView: content)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    @objc private func mediaTypeAllAction() {
        viewModel?.mediaTypeFilter = []
        updateItemStates()
    }

    @objc private func mediaTypeToggleAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let type = MediaType(rawValue: rawValue) else { return }
        if viewModel?.mediaTypeFilter.contains(type) == true {
            viewModel?.mediaTypeFilter.remove(type)
        } else {
            viewModel?.mediaTypeFilter.insert(type)
        }
        updateItemStates()
    }

    @objc private func productionTypeAllAction() {
        viewModel?.productionTypeFilter = []
        updateItemStates()
    }

    @objc private func productionTypeToggleAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let type = ProductionType(rawValue: rawValue) else { return }
        if viewModel?.productionTypeFilter.contains(type) == true {
            viewModel?.productionTypeFilter.remove(type)
        } else {
            viewModel?.productionTypeFilter.insert(type)
        }
        updateItemStates()
    }

    @objc private func sortOrderAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let order = SortOrder(rawValue: rawValue) else { return }
        viewModel?.sortOrder = order
        updateItemStates()
    }

    @objc private func sortAscendingAction(_ sender: NSMenuItem) {
        viewModel?.sortAscending.toggle()
        updateItemStates()
    }
}
