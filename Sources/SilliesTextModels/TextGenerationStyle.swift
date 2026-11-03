import SilliesCore

/// Tasks choose an intent; native adapters translate it into their supported generation options.
package enum TextGenerationStyle: String, Codable, Sendable {
  case precise, conversation, summary

  package func settings(in profile: TextGenerationProfile) -> TextGenerationProfile.Task {
    switch self {
    case .conversation: profile.conversation
    case .summary: profile.summary
    case .precise: profile.precise
    }
  }
}
