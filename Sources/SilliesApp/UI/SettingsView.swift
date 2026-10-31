import SwiftUI

struct SettingsView: View {
  let controller: CompanionController
  var speechModels: SpeechModelsPresentation? = nil
  var textModels: TextModelsPresentation? = nil
  var shortcuts: CommandShortcuts? = nil
  var loginItems: LoginItemSettings? = nil
  var writingTools: WritingTools? = nil
  @State var destination: SettingsDestination = .general

  var body: some View {
    HStack(spacing: 0) {
      navigation
      Divider().overlay(SilliesTheme.border)
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          VStack(alignment: .leading, spacing: 6) {
            Text(destination.title).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(destination.explanation).font(.callout).foregroundStyle(SilliesTheme.secondary)
          }.padding(.bottom, 4)
          page
        }.padding(28).frame(maxWidth: .infinity, alignment: .topLeading)
      }.id(destination)
    }
    .frame(
      minWidth: SettingsWindowLayout.minimumSize.width,
      minHeight: SettingsWindowLayout.minimumSize.height
    )
    .background(SilliesTheme.paper).foregroundStyle(SilliesTheme.ink).tint(SilliesTheme.accent)
  }

  private var navigation: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(spacing: 10) {
        CharacterPortrait(
          renderer: controller.catalog.characters.first?.renderer ?? "cat", size: 36,
          registry: controller.renderers
        ).frame(width: 42, height: 46)
        VStack(alignment: .leading, spacing: 2) {
          Text("sillies").font(.system(size: 24, weight: .bold, design: .rounded))
          Text("Make yourself at home.").font(.system(size: 10)).foregroundStyle(
            SilliesTheme.secondary)
        }
      }
      VStack(spacing: 6) {
        ForEach(SettingsDestination.allCases) { item in
          Button {
            destination = item
          } label: {
            HStack(spacing: 10) {
              Image(systemName: item.symbol).frame(width: 18)
              Text(item.title).font(
                .system(size: 12, weight: destination == item ? .semibold : .medium))
              Spacer(minLength: 0)
              if item == .speech, let count = speechModels?.availableUpdateCount, count > 0 {
                Text("\(count)").font(.caption.bold())
              }
            }.padding(.horizontal, 12).padding(.vertical, 11)
              .foregroundStyle(destination == item ? SilliesTheme.accent : SilliesTheme.ink)
              .background(
                destination == item ? SilliesTheme.accent.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: 10))
          }.buttonStyle(.plain).accessibilityAddTraits(destination == item ? .isSelected : [])
        }
      }
      Spacer()
      Label("On your Mac. In your corner.", systemImage: "lock.shield")
        .font(.system(size: 10)).foregroundStyle(SilliesTheme.secondary)
    }.padding(16).frame(width: SettingsWindowLayout.sidebarWidth)
      .background(SilliesTheme.soft.opacity(0.5))
  }

  @ViewBuilder private var page: some View {
    switch destination {
    case .general:
      GeneralSettingsPage(controller: controller, login: loginItems)
    case .companions:
      CompanionSettingsPage(controller: controller)
    case .writing:
      if let writingTools {
        DictationSettingsView(
          tools: writingTools, hasInsertionAccess: controller.tracker.hasAccessibility,
          shortcuts: shortcuts,
          openShortcuts: { destination = .shortcuts }, openSpeech: { destination = .speech })
      }
    case .speech:
      if let speechModels {
        SpeechSettingsPage(
          model: speechModels, activeModelID: controller.activeSpeechModelID,
          activeDiarizationModelID: controller.activeDiarizationModelID)
      }
    case .intelligence:
      if let textModels { TextModelSettingsView(model: textModels) }
    case .shortcuts:
      if let shortcuts { CommandSettingsView(shortcuts: shortcuts) }
    }
  }
}
