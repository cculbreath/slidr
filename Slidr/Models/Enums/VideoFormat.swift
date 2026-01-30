import AVFoundation

enum VideoFormat: String, Codable, CaseIterable, Sendable {
    case h264MP4
    case hevcMOV

    nonisolated var displayName: String {
        switch self {
        case .h264MP4: return "H.264 (MP4)"
        case .hevcMOV: return "HEVC (MOV)"
        }
    }

    nonisolated var fileExtension: String {
        switch self {
        case .h264MP4: return "mp4"
        case .hevcMOV: return "mov"
        }
    }

    nonisolated var fileType: AVFileType {
        switch self {
        case .h264MP4: return .mp4
        case .hevcMOV: return .mov
        }
    }

    nonisolated var exportPreset: String {
        switch self {
        case .h264MP4: return AVAssetExportPresetHighestQuality
        case .hevcMOV: return AVAssetExportPresetHEVCHighestQuality
        }
    }

    nonisolated var formatDescription: String {
        switch self {
        case .h264MP4:
            return "Most compatible format, works everywhere"
        case .hevcMOV:
            return "Better quality at smaller size, requires macOS 10.13+"
        }
    }
}
