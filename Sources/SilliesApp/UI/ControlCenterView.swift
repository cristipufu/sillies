import SilliesCore
import SilliesWriting
import SwiftUI

struct ControlCenterView: View {
  @Environment(\.silliesTheme) private var theme
  struct Actions {
    let openSettings: () -> Void
    var openVault: () -> Void = {}
    var openStash: () -> Void = {}
    var openCompanions: () -> Void = {}
    var openWriting: () -> Void = {}
    var openConversation: (ConversationMode, String) -> Void = { _, _ in }
    var openSetup: () -> Void = {}
    let quit: () -> Void
  }
  let controller: CompanionController
  let actions: Actions
  var speechModels: SpeechModelsPresentation? = nil
  var dictation: DictationCoordinator? = nil
  @State private var selectedCompanionID = ""
  private var availableCompanions: [CharacterDefinition] {
    controller.catalog.characters.filter {
      $0.chat != nil && controller.settings.enabledCharacters.contains($0.id)
    }
  }
  private var conversationCompanionID: String? {
    availableCompanions.first { $0.id == selectedCompanionID }?.id
      ?? availableCompanions.first { $0.id == controller.skills.activeChatSession?.companionID }?.id
      ?? availableCompanions.first?.id
  }

  var body: some View {
    @Bindable var settings = controller.settings
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 11) {
        Image(systemName: "sparkles")
          .font(.system(size: 21, weight: .medium)).foregroundStyle(theme.accent)
          .frame(width: 44, height: 44).background(
            theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: "sillies").font(.system(size: 28, weight: .bold, design: .rounded))
            .tracking(-0.9)
          Text("Your workspace, with a little life.").font(.system(size: 11))
            .foregroundStyle(theme.secondary)
        }
        Spacer(minLength: 0)
        Button {
          settings.paused.toggle()
        } label: {
          Image(systemName: settings.paused ? "play.fill" : "pause.fill")
            .font(.system(size: 12, weight: .semibold)).frame(width: 31, height: 31)
            .background(theme.soft, in: Circle())
        }.buttonStyle(.plain).help(
          settings.paused
            ? String(localized: "Resume companions") : String(localized: "Pause companions")
        )
        .accessibilityLabel(
          settings.paused
            ? String(localized: "Resume companions") : String(localized: "Pause companions"))
      }

      HStack(spacing: 7) {
        Circle().fill(
          settings.paused || controller.isExcluded
            ? theme.warning : theme.success
        ).frame(width: 6, height: 6)
        Text(controller.restingDescription).font(.system(size: 11, weight: .medium)).lineLimit(1)
          .foregroundStyle(theme.secondary)
      }

      HStack {
        if let session = controller.skills.activeAudioSession {
          Button("Open \(session.kind.title)", systemImage: "waveform") {
            controller.skills.onOpenAudioSession?(session)
          }
          Spacer()
          Button("Finish", action: { session.onFinish?() })
        } else if let dictation, dictation.phase != .idle {
          Button("Open Dictate", systemImage: "waveform") { actions.openWriting() }
          Spacer()
          if dictation.canFinish {
            Button("Finish") { dictation.finish() }
          } else {
            Button(dictation.isActive ? String(localized: "Cancel") : String(localized: "Dismiss"))
            { dictation.dismiss() }
          }
        } else if let session = controller.skills.activeChatSession {
          Button(
            "Open \(session.mode == .talk ? String(localized: "Talk") : String(localized: "Chat"))",
            systemImage: session.mode == .talk ? "waveform" : "text.bubble"
          ) {
            actions.openConversation(session.mode, session.companionID)
          }
          Spacer()
          if session.isVoiceConversationActive {
            Button("End voice") { session.stopVoiceConversation() }
          }
        } else {
          Button("Record microphone", systemImage: "mic.fill") {
            controller.startMicrophoneRecording()
          }
          .disabled(!controller.shouldRun || controller.liveCount == 0)
          Spacer()
          Button("Pocket Stash", systemImage: "tray") { actions.openStash() }
        }
      }.font(.system(size: 12, weight: .medium))

      VStack(alignment: .leading, spacing: 10) {
        Picker(
          "Companion",
          selection: Binding(
            get: { conversationCompanionID ?? "" }, set: { selectedCompanionID = $0 })
        ) {
          ForEach(availableCompanions) { Text($0.name).tag($0.id) }
        }.disabled(availableCompanions.isEmpty)
        HStack(spacing: 10) {
          Button("Chat", systemImage: "text.bubble") { beginConversation(.chat) }
          Button("Talk", systemImage: "waveform") { beginConversation(.talk) }
          Spacer()
          Button {
            controller.greet()
          } label: {
            Image(systemName: "hand.wave")
          }
          .help("Say hello").accessibilityLabel("Say hello")
        }.buttonStyle(SoftButtonStyle()).disabled(conversationCompanionID == nil)
      }

      HStack {
        Text("Your crew").font(.callout.weight(.semibold))
        Spacer()
        Button("Manage crew", action: actions.openCompanions)
          .font(.caption).buttonStyle(.plain).foregroundStyle(theme.accent)
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6)
      {
        ForEach(controller.catalog.characters) { character in
          compactCompanion(character)
        }
      }
      HStack {
        Label("Energy", systemImage: "leaf").font(.callout)
        Spacer()
        Picker("Energy", selection: $settings.activity) {
          ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
        }.labelsHidden().pickerStyle(.segmented).frame(width: 180)
      }

      Button(action: actions.openVault) {
        HStack(spacing: 9) {
          Image(systemName: "archivebox.fill")
            .foregroundStyle(theme.accent)
          VStack(alignment: .leading, spacing: 3) {
            Text("Session Vault").font(.system(size: 11, weight: .semibold))
            Text(
              controller.savedRecordCount == 0
                ? String(localized: "Drag a companion onto a window to capture or listen.")
                : String(
                  localized: "\(controller.savedRecordCount) saved captures, transcripts & stashes",
                  comment: "plural")
            )
            .font(.system(size: 10))
            .foregroundStyle(theme.secondary)
            .lineLimit(1)
          }
          Spacer()
          Image(systemName: "arrow.up.right").font(.system(size: 11))
        }.padding(12).background(
          theme.card, in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12).strokeBorder(
            theme.border.opacity(0.7), lineWidth: 0.7))
      }.buttonStyle(.plain)

      if let speechModels, speechModels.availableUpdateCount > 0 {
        Button("Model updates available", systemImage: "arrow.down.circle") {
          actions.openSettings()
        }
        .font(.caption.weight(.medium)).buttonStyle(.plain).foregroundStyle(theme.accent)
      }

      HStack {
        Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(theme.danger)
        Text("A little company. All on your Mac.").font(.system(size: 9)).foregroundStyle(
          theme.secondary)
        Spacer()
        Button("Start here", action: actions.openSetup).buttonStyle(.plain)
          .font(.caption).foregroundStyle(theme.accent)
        Button(action: actions.openSettings) {
          Image(systemName: "slider.horizontal.3").font(.system(size: 12))
        }
        .buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
        Button(action: actions.quit) { Image(systemName: "power").font(.system(size: 11)) }
          .buttonStyle(.plain).padding(.leading, 7).help("Quit Sillies").accessibilityLabel(
            "Quit Sillies")
      }
    }.padding(22).frame(width: ControlCenterLayout.width).background(theme.paper)
      .foregroundStyle(theme.ink)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func beginConversation(_ mode: ConversationMode) {
    guard let id = conversationCompanionID else { return }
    actions.openConversation(mode, id)
  }

  private func compactCompanion(_ character: CharacterDefinition) -> some View {
    let enabled = controller.settings.enabledCharacters.contains(character.id)
    return Button {
      controller.settings.toggleCharacter(character.id)
    } label: {
      VStack(spacing: 3) {
        CharacterPortrait(renderer: character.renderer, size: 32, registry: controller.renderers)
          .frame(width: 36, height: 38)
          .opacity(enabled ? 1 : 0.65)
        Text(character.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
      }
      .frame(maxWidth: .infinity).padding(.vertical, 5)
      .background(
        enabled ? theme.accent.opacity(0.12) : theme.card, in: RoundedRectangle(cornerRadius: 10)
      )
      .overlay(alignment: .topTrailing) {
        if enabled {
          Image(systemName: "checkmark.circle.fill").font(.system(size: 8)).foregroundStyle(
            theme.accent
          ).padding(3)
        }
      }
    }.buttonStyle(.plain).accessibilityLabel(character.name)
      .accessibilityValue(
        enabled ? String(localized: "Selected") : String(localized: "Not selected")
      )
      .accessibilityAddTraits(enabled ? .isSelected : [])
  }

}

extension Color {
  init(hex: String) { self.init(nsColor: NSColor(hex: hex)) }
}
