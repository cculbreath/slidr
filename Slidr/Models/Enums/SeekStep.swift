import Foundation

enum SeekStep: CaseIterable, Sendable {
    case frame           // ~0.04s at 24fps
    case halfSecond      // 0.5s
    case oneSecond       // 1s
    case fiveSeconds     // 5s
    case tenSeconds      // 10s
    case thirtySeconds   // 30s
    case oneMinute       // 60s

    var seconds: Double {
        switch self {
        case .frame: return 1.0 / 24.0  // Approximate, actual depends on video
        case .halfSecond: return 0.5
        case .oneSecond: return 1.0
        case .fiveSeconds: return 5.0
        case .tenSeconds: return 10.0
        case .thirtySeconds: return 30.0
        case .oneMinute: return 60.0
        }
    }
}
