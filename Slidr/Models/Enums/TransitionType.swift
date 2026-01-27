import SwiftUI

enum TransitionType: String, Codable, CaseIterable {
    case none
    case crossfade
    case slideLeft
    case slideRight
    case zoom

    var displayName: String {
        switch self {
        case .none: return "None"
        case .crossfade: return "Crossfade"
        case .slideLeft: return "Slide Left"
        case .slideRight: return "Slide Right"
        case .zoom: return "Zoom"
        }
    }

    var enterTransition: AnyTransition {
        switch self {
        case .none:
            return .identity
        case .crossfade:
            return .opacity
        case .slideLeft:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .slideRight:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        case .zoom:
            return .asymmetric(
                insertion: .scale(scale: 1.1).combined(with: .opacity),
                removal: .scale(scale: 0.9).combined(with: .opacity)
            )
        }
    }

    var exitTransition: AnyTransition {
        switch self {
        case .none:
            return .identity
        case .crossfade:
            return .opacity
        case .slideLeft:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        case .slideRight:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .zoom:
            return .asymmetric(
                insertion: .scale(scale: 0.9).combined(with: .opacity),
                removal: .scale(scale: 1.1).combined(with: .opacity)
            )
        }
    }
}
