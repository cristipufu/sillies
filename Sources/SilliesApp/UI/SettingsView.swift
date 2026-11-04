import SwiftUI

struct SettingsView: View {
  @Environment(\.silliesTheme) private var theme
  let controller: CompanionController
  var appearance: AppearancePreferences? = nil
  var language: LanguagePreferences? = nil
  var speechModels: SpeechModelsPresentation? = nil
  var voiceModels: VoiceModelsPresentation? = nil
  var textModels: TextModelsPresentation? = nil
  var searchModels: SearchModelsPresentation? = nil
  var shortcuts: CommandShortcuts? = nil
  var loginItems: LoginItemSettings? = nil
  var writingTools: WritingTools? = nil
  @Bindable var navigation = SettingsNavigation()
  private var destination: SettingsDestination { navigation.destination }

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider().overlay(theme.border)
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          VStack(alignment: .leading, spacing: 6) {
            Text(destination.title).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(destination.explanation).font(.callout).foregroundStyle(theme.secondary)
          }.padding(.bottom, 4)
          page
        }.padding(28).frame(maxWidth: .infinity, alignment: .topLeading)
      }.id(destination)
    }
    .frame(
      minWidth: SettingsWindowLayout.minimumSize.width,
      minHeight: SettingsWindowLayout.minimumSize.height
    )
    .background(theme.paper).foregroundStyle(theme.ink).tint(theme.accent)
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(spacing: 10) {
        CharacterPortrait(
          renderer: controller.catalog.characters.first?.renderer ?? "cat", size: 36,
          registry: controller.renderers
        ).frame(width: 42, height: 46)
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: "sillies").font(.system(size: 24, weight: .bold, design: .rounded))
          Text("Make yourself at home.").font(.system(size: 10)).foregroundStyle(
            theme.secondary)
        }
      }
      VStack(spacing: 6) {
        ForEach(SettingsDestination.allCases) { item in
          Button {
            navigation.destination = item
          } label: {
            HStack(spacing: 10) {
              Image(systemName: item.symbol).frame(width: 18)
              Text(item.title).font(
                .system(size: 12, weight: destination == item ? .semibold : .medium)
              )
              .fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: 0)
              if item == .speech, let count = speechModels?.availableUpdateCount, count > 0 {
                Text("\(count)").font(.caption.bold())
              }
            }.padding(.horizontal, 12).padding(.vertical, 11)
              .foregroundStyle(destination == item ? theme.accent : theme.ink)
              .background(
                destination == item ? theme.accent.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: 10))
          }.buttonStyle(.plain).accessibilityAddTraits(destination == item ? .isSelected : [])
        }
      }
      Spacer()
      Label("On your Mac. In your corner.", systemImage: "lock.shield")
        .font(.system(size: 10)).foregroundStyle(theme.secondary)
    }.padding(16).frame(width: SettingsWindowLayout.sidebarWidth)
      .background(theme.soft.opacity(0.5))
  }

  @ViewBuilder private var page: some View {
    switch destination {
    case .general:
      GeneralSettingsPage(controller: controller, login: loginItems, language: language)
    case .appearance:
      if let appearance { AppearanceSettingsPage(model: appearance) }
    case .companions:
      CompanionSettingsPage(controller: controller)
    case .writing:
      if let writingTools {
        DictationSettingsView(
          tools: writingTools, hasInsertionAccess: controller.tracker.hasAccessibility,
          shortcuts: shortcuts,
          openShortcuts: { navigation.destination = .shortcuts },
          openSpeech: { navigation.destination = .speech })
      }
    case .speech:
      if let speechModels {
        SpeechSettingsPage(
          model: speechModels, activeModelID: controller.activeSpeechModelID,
          activeDiarizationModelID: controller.activeDiarizationModelID)
      }
    case .intelligence:
      if let textModels { TextModelSettingsView(model: textModels) }
    case .search:
      if let searchModels { SearchModelSettingsView(model: searchModels) }
    case .voices:
      if let voiceModels { VoiceModelSettingsView(model: voiceModels) }
    case .shortcuts:
      if let shortcuts { CommandSettingsView(shortcuts: shortcuts) }
    }
  }
}
