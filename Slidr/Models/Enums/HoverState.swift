enum HoverState: Equatable {
    case idle
    case scrubbing(position: Double)
    case pendingPlayback(position: Double)
    case playing(position: Double)

    var position: Double {
        switch self {
        case .idle: return 0
        case .scrubbing(let p), .pendingPlayback(let p), .playing(let p): return p
        }
    }

    var isScrubbing: Bool {
        if case .scrubbing = self { return true }
        return false
    }

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    var isPendingPlayback: Bool {
        if case .pendingPlayback = self { return true }
        return false
    }

    var isActive: Bool {
        self != .idle
    }
}
