enum ListColumnID: String, CaseIterable, Identifiable {
    case thumbnail
    case title
    case filename
    case mediaType
    case tags
    case caption
    case hasTranscript
    case summary
    case duration
    case fileSize
    case dateImported
    case dateModified
    case rating
    case production
    case source
    case dimensions
    case frameRate
    case hasAudio
    case frameCount
    case favorite
    case storageLocation
    case status

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thumbnail: return "Thumbnail"
        case .title: return "Title"
        case .filename: return "Filename"
        case .mediaType: return "Media Type"
        case .tags: return "Tags"
        case .caption: return "Caption"
        case .hasTranscript: return "Has Transcript"
        case .summary: return "Summary"
        case .duration: return "Duration"
        case .fileSize: return "File Size"
        case .dateImported: return "Date Imported"
        case .dateModified: return "Date Modified"
        case .rating: return "Rating"
        case .production: return "Production Type"
        case .source: return "Source"
        case .dimensions: return "Dimensions"
        case .frameRate: return "Frame Rate"
        case .hasAudio: return "Has Audio"
        case .frameCount: return "Frame Count"
        case .favorite: return "Favorite"
        case .storageLocation: return "Storage Location"
        case .status: return "Status"
        }
    }

    var defaultVisible: Bool {
        switch self {
        case .thumbnail, .title, .mediaType, .tags, .duration, .rating, .fileSize, .dateImported:
            return true
        default:
            return false
        }
    }
}
