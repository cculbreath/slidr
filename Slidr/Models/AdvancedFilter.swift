import Foundation

// MARK: - AdvancedFilter

struct AdvancedFilter {
    var searchText: String = ""
    var rules: [FilterRule] = []
    var combineMode: CombineMode = .all

    var isEmpty: Bool {
        searchText.isEmpty && rules.isEmpty
    }

    func matches(_ item: MediaItem) -> Bool {
        // Search text filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            let matchesSearch = item.originalFilename.lowercased().contains(query)
                || item.tags.contains(where: { $0.lowercased().contains(query) })
                || (item.caption?.lowercased().contains(query) ?? false)
                || (item.transcriptText?.lowercased().contains(query) ?? false)
                || (item.summary?.lowercased().contains(query) ?? false)
            if !matchesSearch { return false }
        }

        guard !rules.isEmpty else { return true }

        switch combineMode {
        case .all:
            return rules.allSatisfy { $0.matches(item) }
        case .any:
            return rules.contains { $0.matches(item) }
        }
    }

    func applyToPlaylist(_ playlist: Playlist) {
        if !searchText.isEmpty {
            playlist.filterSearchText = searchText
        }

        var productionTypes: [String] = []
        var includeTags: [String] = []
        var excludeTags: [String] = []
        var hasTranscript: Bool?
        var hasCaption: Bool?

        for rule in rules {
            switch rule.field {
            case .tag:
                if case .string(let value) = rule.value {
                    switch rule.condition {
                    case .contains, .is:
                        includeTags.append(value)
                    case .doesNotContain, .isNot:
                        excludeTags.append(value)
                    default:
                        break
                    }
                }
            case .productionType:
                if case .productionType(let type) = rule.value {
                    switch rule.condition {
                    case .is:
                        productionTypes.append(type.rawValue)
                    default:
                        break
                    }
                }
            case .mediaType:
                if case .mediaType(let type) = rule.value {
                    switch rule.condition {
                    case .is:
                        if playlist.filterMediaTypes == nil {
                            playlist.filterMediaTypes = []
                        }
                        playlist.filterMediaTypes?.append(type.rawValue)
                    default:
                        break
                    }
                }
            case .duration:
                if case .duration(let seconds) = rule.value {
                    switch rule.condition {
                    case .greaterThan:
                        playlist.filterMinDuration = seconds
                    case .lessThan:
                        playlist.filterMaxDuration = seconds
                    default:
                        break
                    }
                }
            case .rating:
                if case .rating(let rating) = rule.value {
                    switch rule.condition {
                    case .is, .greaterThan:
                        playlist.filterMinRating = rating
                    default:
                        break
                    }
                }
            case .hasTranscript:
                hasTranscript = true
            case .hasCaption:
                hasCaption = true
            }
        }

        if !productionTypes.isEmpty {
            playlist.filterProductionTypes = productionTypes
        }
        if !includeTags.isEmpty {
            playlist.filterTags = includeTags
        }
        if !excludeTags.isEmpty {
            playlist.filterTagsExcluded = excludeTags
        }
        if let hasTranscript {
            playlist.filterHasTranscript = hasTranscript
        }
        if let hasCaption {
            playlist.filterHasCaption = hasCaption
        }
    }
}

// MARK: - CombineMode

enum CombineMode: String, CaseIterable {
    case all = "All"
    case any = "Any"
}

// MARK: - FilterRule

struct FilterRule: Identifiable {
    let id: UUID
    var field: FilterField
    var condition: FilterCondition
    var value: FilterValue

    init(field: FilterField = .tag, condition: FilterCondition? = nil, value: FilterValue? = nil) {
        self.id = UUID()
        self.field = field
        self.condition = condition ?? field.availableConditions.first ?? .contains
        self.value = value ?? field.defaultValue
    }

    func matches(_ item: MediaItem) -> Bool {
        switch field {
        case .tag:
            guard case .string(let tagValue) = value else { return true }
            let query = tagValue.lowercased()
            switch condition {
            case .contains:
                return item.tags.contains { $0.lowercased().contains(query) }
            case .doesNotContain:
                return !item.tags.contains { $0.lowercased().contains(query) }
            case .is:
                return item.tags.contains { $0.lowercased() == query }
            case .isNot:
                return !item.tags.contains { $0.lowercased() == query }
            default:
                return true
            }

        case .mediaType:
            guard case .mediaType(let type) = value else { return true }
            switch condition {
            case .is: return item.mediaType == type
            case .isNot: return item.mediaType != type
            default: return true
            }

        case .productionType:
            guard case .productionType(let type) = value else { return true }
            switch condition {
            case .is: return item.production == type
            case .isNot: return item.production != type
            default: return true
            }

        case .duration:
            guard case .duration(let seconds) = value else { return true }
            let itemDuration = item.duration ?? 0
            switch condition {
            case .greaterThan: return itemDuration > seconds
            case .lessThan: return itemDuration < seconds
            case .is: return abs(itemDuration - seconds) < 1
            default: return true
            }

        case .rating:
            guard case .rating(let rating) = value else { return true }
            let itemRating = item.rating ?? 0
            switch condition {
            case .is: return itemRating == rating
            case .greaterThan: return itemRating > rating
            case .lessThan: return itemRating < rating
            default: return true
            }

        case .hasTranscript:
            return item.hasTranscript

        case .hasCaption:
            return item.hasCaption
        }
    }
}

// MARK: - FilterField

enum FilterField: String, CaseIterable {
    case tag = "Tag"
    case mediaType = "Media Type"
    case productionType = "Production Type"
    case duration = "Duration"
    case rating = "Rating"
    case hasTranscript = "Has Transcript"
    case hasCaption = "Has Caption"

    var availableConditions: [FilterCondition] {
        switch self {
        case .tag:
            return [.contains, .doesNotContain, .is, .isNot]
        case .mediaType, .productionType:
            return [.is, .isNot]
        case .duration:
            return [.greaterThan, .lessThan]
        case .rating:
            return [.is, .greaterThan, .lessThan]
        case .hasTranscript, .hasCaption:
            return []
        }
    }

    var defaultValue: FilterValue {
        switch self {
        case .tag: return .string("")
        case .mediaType: return .mediaType(.video)
        case .productionType: return .productionType(.professional)
        case .duration: return .duration(30)
        case .rating: return .rating(3)
        case .hasTranscript: return .boolean(true)
        case .hasCaption: return .boolean(true)
        }
    }
}

// MARK: - FilterCondition

enum FilterCondition: String, CaseIterable {
    case contains = "contains"
    case doesNotContain = "does not contain"
    case `is` = "is"
    case isNot = "is not"
    case greaterThan = "greater than"
    case lessThan = "less than"
}

// MARK: - FilterValue

enum FilterValue {
    case string(String)
    case mediaType(MediaType)
    case productionType(ProductionType)
    case duration(TimeInterval)
    case rating(Int)
    case boolean(Bool)
}
