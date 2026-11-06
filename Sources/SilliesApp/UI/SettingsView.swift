import SilliesCore
import SwiftUI

struct SettingsView: View {
  struct Actions {
    let openRetention: () -> Void
    let openMemories: (String) -> SessionFailure?
  }
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
  var diagnostics: DiagnosticsPresentation? = nil
  var setup: SetupPresentation? = nil
  var suggestions: SetupModelSuggestions? = nil
  var companionPreferences: CompanionPreferences? = nil
  var exportDiagnostics: () -> Void = {}
  var actions: Actions?
  @Bindable var navigation = SettingsNavigation()
  private var destination: SettingsDestination { navigation.destination }

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider().overlay(theme.border)
      if destination == .setup, let setup, let suggestions, let textModels, let voiceModels {
        SetupView(
          model: setup, registry: controller.renderers, textModels: textModels,
          voiceModels: voiceModels, suggestions: suggestions
        )
        .task { setup.refresh() }
        .onDisappear { setup.stop() }
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            if navigation.returnsToSetup {
              Button("Back to setup", systemImage: "arrow.left") {
                navigation.destination = .setup
                navigation.returnsToSetup = false
              }.buttonStyle(.plain).foregroundStyle(theme.accent)
            }
            VStack(alignment: .leading, spacing: 6) {
              Text(destination.title).font(.system(size: 26, weight: .bold, design: .rounded))
              Text(destination.explanation).font(.callout).foregroundStyle(theme.secondary)
            }.padding(.bottom, 4)
            if let failure = navigation.failure {
              SessionFailureNotice(failure: failure)
            }
            page
          }.padding(28).frame(maxWidth: .infinity, alignment: .topLeading)
        }.id(destination)
      }
    }
    .frame(
      minWidth: SettingsWindowLayout.minimumSize.width,
      minHeight: SettingsWindowLayout.minimumSize.height
    )
    .background(theme.paper).foregroundStyle(theme.ink).tint(theme.accent)
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 20) {
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
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(SettingsGroup.allCases) { group in
            VStack(alignment: .leading, spacing: 4) {
              Text(group.title).font(.caption.weight(.semibold)).foregroundStyle(theme.secondary)
                .padding(.horizontal, 12)
              ForEach(group.destinations) { item in
                Button {
                  navigation.destination = item
                  navigation.failure = nil
                  navigation.returnsToSetup = false
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
                  }.padding(.horizontal, 12).padding(.vertical, 8)
                    .foregroundStyle(destination == item ? theme.accent : theme.ink)
                    .background(
                      destination == item ? theme.accent.opacity(0.12) : .clear,
                      in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityAddTraits(destination == item ? .isSelected : [])
              }
            }
          }
          if let actions {
            Button("Retention…", systemImage: "archivebox") { actions.openRetention() }
              .buttonStyle(.plain).font(.callout).padding(.horizontal, 12)
          }
        }
      }
      Label("On your Mac. In your corner.", systemImage: "lock.shield")
        .font(.system(size: 10)).foregroundStyle(theme.secondary)
    }.padding(16).frame(width: SettingsWindowLayout.sidebarWidth)
      .background(theme.soft.opacity(0.5))
  }

  @ViewBuilder private var page: some View {
    switch destination {
    case .setup:
      Text("Open Sillies normally to set up your companions.")
    case .general:
      GeneralSettingsPage(
        controller: controller, login: loginItems, language: language,
        diagnostics: diagnostics, exportDiagnostics: exportDiagnostics)
    case .appearance:
      if let appearance { AppearanceSettingsPage(model: appearance) }
    case .companions:
      Picker("Companions", selection: $navigation.companionsPage) {
        Text("Your crew").tag(SettingsNavigation.CompanionsPage.crew)
        Text("Companion profile").tag(SettingsNavigation.CompanionsPage.profile)
      }.pickerStyle(.segmented)
      if navigation.companionsPage == .crew {
        CompanionSettingsPage(controller: controller)
      } else if let companionPreferences, let textModels, let voiceModels {
        CompanionProfilesSettingsView(
          characters: controller.catalog.characters,
          preferences: companionPreferences, textModels: textModels, voiceModels: voiceModels,
          selectedID: $navigation.selectedCompanionID,
          openMemories: actions.map { actions in
            { navigation.failure = actions.openMemories($0) }
          })
      }
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
      Button("Memories", systemImage: "brain.head.profile") {
        navigation.showProfile(navigation.selectedCompanionID)
      }.buttonStyle(SoftButtonStyle())
    case .voices:
      if let voiceModels { VoiceModelSettingsView(model: voiceModels) }
    case .shortcuts:
      if let shortcuts { CommandSettingsView(shortcuts: shortcuts) }
    }
  }
}
