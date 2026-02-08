import Foundation

enum TranscriptionProvider: String, Codable, Sendable, CaseIterable {
    case groqWhisper
    case mistral

    var displayName: String {
        switch self {
        case .groqWhisper: return "Groq Whisper"
        case .mistral: return "Mistral Voxtral"
        }
    }
}
