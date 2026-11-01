import Observation
import SwiftUI

@MainActor @Observable final class SettingsNavigation {
  var destination: SettingsDestination
  init(destination: SettingsDestination = .general) { self.destination = destination }
}

enum SettingsDestination: String, CaseIterable, Identifiable {
  case general, appearance, companions, writing, speech, intelligence, voices, shortcuts
  var id: Self { self }
  var title: String {
    switch self {
    case .general: String(localized: "General")
    case .appearance: String(localized: "Appearance")
    case .companions: String(localized: "Companions")
    case .writing: String(localized: "Dictation & Writing")
    case .speech: String(localized: "Speech & Meetings")
    case .intelligence: String(localized: "Local AI")
    case .voices: String(localized: "Voices")
    case .shortcuts: String(localized: "Shortcuts")
    }
  }
  var symbol: String {
    switch self {
    case .general: "slider.horizontal.3"
    case .appearance: "paintpalette"
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
    case .general: String(localized: "Make Sillies part of your day.")
    case .appearance: String(localized: "A familiar little world, in your colors.")
    case .companions: String(localized: "Choose your crew and how they spend their time.")
    case .writing: String(localized: "Your voice, your words, in the app you’re using.")
    case .speech: String(localized: "Local speech models for dictation and meetings.")
    case .intelligence:
      String(localized: "Optional local models for multilingual notes and writing.")
    case .voices: String(localized: "Give your companions a voice, entirely on your Mac.")
    case .shortcuts: String(localized: "A keyboard path to your companions’ skills.")
    }
  }
}

enum SettingsWindowLayout {
  static let initialSize = CGSize(width: 900, height: 720)
  static let minimumSize = CGSize(width: 820, height: 620)
  static let sidebarWidth: CGFloat = 200
}

struct SettingsCard<Content: View>: View {
  @Environment(\.silliesTheme) private var theme
  let title: String
  var detail: String? = nil
  @ViewBuilder let content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
        if let detail { Text(detail).font(.callout).foregroundStyle(theme.secondary) }
      }
      content().font(.callout)
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.card, in: RoundedRectangle(cornerRadius: 15))
      .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(theme.border, lineWidth: 0.8))
  }
}
