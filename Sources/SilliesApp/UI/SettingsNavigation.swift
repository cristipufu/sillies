import Observation
import SwiftUI

@MainActor @Observable final class SettingsNavigation {
  var destination: SettingsDestination
  init(destination: SettingsDestination = .general) { self.destination = destination }
}

enum SettingsDestination: String, CaseIterable, Identifiable {
  case general, companions, writing, speech, intelligence, voices, shortcuts
  var id: Self { self }
  var title: String {
    switch self {
    case .general: "General"
    case .companions: "Companions"
    case .writing: "Dictation & Writing"
    case .speech: "Speech & Meetings"
    case .intelligence: "Local AI"
    case .voices: "Voices"
    case .shortcuts: "Shortcuts"
    }
  }
  var symbol: String {
    switch self {
    case .general: "slider.horizontal.3"
    case .companions: "pawprint.fill"
    case .writing: "mic.fill"
    case .speech: "waveform"
    case .intelligence: "sparkles"
    case .voices: "speaker.wave.2"
    case .shortcuts: "keyboard"
    }
  }
  var explanation: String {
    switch self {
    case .general: "Make Sillies part of your day."
    case .companions: "Choose your crew and how they spend their time."
    case .writing: "Your voice, your words, in the app you’re using."
    case .speech: "Local speech models for dictation and meetings."
    case .intelligence: "Optional local models for multilingual notes and writing."
    case .voices: "Give your companions a voice, entirely on your Mac."
    case .shortcuts: "A keyboard path to your companions’ skills."
    }
  }
}

enum SettingsWindowLayout {
  static let initialSize = CGSize(width: 900, height: 720)
  static let minimumSize = CGSize(width: 820, height: 620)
  static let sidebarWidth: CGFloat = 200
}

struct SettingsCard<Content: View>: View {
  let title: String
  var detail: String? = nil
  @ViewBuilder let content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
        if let detail { Text(detail).font(.callout).foregroundStyle(SilliesTheme.secondary) }
      }
      content().font(.callout)
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
      .background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 15))
      .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(SilliesTheme.border, lineWidth: 0.8))
  }
}
