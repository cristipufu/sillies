import Observation
import SilliesChat
import SwiftUI

@MainActor @Observable final class SettingsNavigation {
  var destination: SettingsDestination
  var returnsToSetup = false
  init(destination: SettingsDestination = .general) { self.destination = destination }

  func showConversationSettings(
    _ requested: ChatNotice.SettingsDestination, setup: SetupPresentation
  ) {
    returnsToSetup = false
    switch requested {
    case .companionProfile:
      setup.move(to: .preparation)
      setup.isProfileExpanded = true
      destination = .setup
    case .textModels where setup.replyModelOverride != nil:
      setup.move(to: .preparation)
      setup.isProfileExpanded = true
      destination = .setup
    case .textModels: destination = .intelligence
    case .voices: destination = .voices
    case .recognition: destination = .speech
    }
  }
}

enum SettingsDestination: String, CaseIterable, Identifiable {
  case setup, general, appearance, companions, writing, speech, intelligence, search, voices,
    shortcuts
  var id: Self { self }
  var title: String {
    switch self {
    case .setup: String(localized: "Start here")
    case .general: String(localized: "General")
    case .appearance: String(localized: "Appearance")
    case .companions: String(localized: "Companions")
    case .writing: String(localized: "Dictation & Writing")
    case .speech: String(localized: "Speech & Meetings")
    case .intelligence: String(localized: "Local AI")
    case .search: String(localized: "Search & Memory")
    case .voices: String(localized: "Voices")
    case .shortcuts: String(localized: "Shortcuts")
    }
  }
  var symbol: String {
    switch self {
    case .setup: "sparkles"
    case .general: "slider.horizontal.3"
    case .appearance: "paintpalette"
    case .companions: "pawprint.fill"
    case .writing: "mic.fill"
    case .speech: "waveform"
    case .intelligence: "sparkles"
    case .search: "brain.head.profile"
    case .voices: "speaker.wave.2"
    case .shortcuts: "keyboard"
    }
  }
  var explanation: String {
    switch self {
    case .setup: String(localized: "A little help getting settled.")
    case .general: String(localized: "Make Sillies part of your day.")
    case .appearance: String(localized: "A familiar little world, in your colors.")
    case .companions: String(localized: "Choose your crew and how they spend their time.")
    case .writing: String(localized: "Your voice, your words, in the app you’re using.")
    case .speech: String(localized: "Speech recognition for Talk, dictation and meetings.")
    case .intelligence:
      String(localized: "Local models for conversations, meeting notes and writing.")
    case .search: String(localized: "Help your companions find the memories that matter.")
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
