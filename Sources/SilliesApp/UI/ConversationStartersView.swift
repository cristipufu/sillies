import SilliesChat
import SwiftUI

enum ConversationStarter: String, CaseIterable, Identifiable {
  case recording, savedItem, language, continueTopic
  var id: Self { self }
  var title: String {
    switch self {
    case .recording: String(localized: "Discuss a recording")
    case .savedItem: String(localized: "Find something saved")
    case .language: String(localized: "Practise a language")
    case .continueTopic: String(localized: "Pick up our last topic")
    }
  }
  var symbol: String {
    switch self {
    case .recording: "waveform"
    case .savedItem: "tray.full"
    case .language: "bubble.left.and.bubble.right"
    case .continueTopic: "arrow.uturn.backward"
    }
  }
  func draft(language: String) -> String {
    switch self {
    case .recording: String(localized: "Can we discuss a recent recording in my Vault?")
    case .savedItem: String(localized: "Help me find something I saved in my Vault.")
    case .language:
      String(localized: "Let’s practise \(language) together. Ask me about my level.")
    case .continueTopic: String(localized: "Let’s pick up our last topic. Where did we leave off?")
    }
  }
}

struct ConversationStartersView: View {
  @Environment(\.silliesTheme) private var theme
  let model: ChatSession
  let selected: () -> Void
  private enum Layout {
    static let spacing: CGFloat = 8
    static let contentSpacing: CGFloat = 10
    static let iconWidth: CGFloat = 20
    static let minimumGap: CGFloat = 4
    static let inset: CGFloat = 12
    static let cornerRadius: CGFloat = 12
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Layout.spacing) {
      ForEach(
        ConversationStarter.allCases.filter { $0 != .continueTopic || !model.messages.isEmpty }
      ) { starter in
        Button {
          let language =
            Locale.current.localizedString(forIdentifier: model.language) ?? model.language
          if model.useSuggestedDraft(starter.draft(language: language)) { selected() }
        } label: {
          HStack(spacing: Layout.contentSpacing) {
            Image(systemName: starter.symbol).frame(width: Layout.iconWidth).foregroundStyle(
              theme.accent)
            Text(starter.title).multilineTextAlignment(.leading)
            Spacer(minLength: Layout.minimumGap)
            Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(theme.secondary)
          }.font(.callout).padding(Layout.inset).contentShape(Rectangle())
        }.buttonStyle(.plain).background(
          theme.card, in: RoundedRectangle(cornerRadius: Layout.cornerRadius)
        )
        .disabled(!model.draft.isEmpty || !model.canCompose)
      }
      Text(
        model.draft.isEmpty
          ? String(localized: "Pick an idea, then make it your own.")
          : String(localized: "Your draft is kept. Send or clear it to choose an idea.")
      )
      .font(.caption).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
}
