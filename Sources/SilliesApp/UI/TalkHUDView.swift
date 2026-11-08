import SilliesChat
import SwiftUI

/// Compact controls sit inside the same native bubble artwork as meeting thoughts.
struct TalkHUDView: View {
  private static let contentWidth: CGFloat = 206
  private static let noticePadding: CGFloat = 16
  private static let attributionSpacing: CGFloat = 4
  private static let noticeSize = CGSize(width: 320, height: 200)
  @Environment(\.silliesTheme) private var theme
  let model: ChatSession
  let openTranscript: () -> Void
  let openSettings: (ChatNotice.SettingsDestination) -> Void
  @State private var showsNotice = false

  private var notice: String? {
    model.failure?.message ?? model.history.failure ?? model.notice?.message
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Self.attributionSpacing) {
      controls
      if let attribution = model.voiceAttribution {
        ModelAttributionLink(attribution: attribution)
          .frame(maxWidth: Self.contentWidth, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }
    }.padding(SessionHUDMetrics.contentInset)
  }

  private var controls: some View {
    HStack(spacing: SessionHUDMetrics.spacing) {
      SessionAudioIndicator(level: model.audioLevel, isCapturing: model.isVoiceConversationActive)
      SessionHUDLabel(
        title: model.companionName,
        status: notice ?? model.status, layout: .flexible
      )
      .accessibilityLabel(String(localized: "Talk · \(model.companionName)"))
      if notice != nil { noticeButton }
      Button(action: openTranscript) {
        controlIcon("text.bubble")
      }.help("Open session and transcript").accessibilityLabel("Transcript")
      microphoneButton
      playbackButton
      SessionHUDDismiss(title: String(localized: "End voice")) { model.onFinish?() }
    }.buttonStyle(.plain).foregroundStyle(theme.ink).tint(theme.accent)
      .frame(
        width: Self.contentWidth
          + (notice == nil ? 0 : SessionHUDMetrics.controlSize + SessionHUDMetrics.spacing)
      )
  }

  private var noticeButton: some View {
    Button {
      showsNotice = true
    } label: {
      controlIcon("exclamationmark.triangle.fill").foregroundStyle(theme.warning)
    }.help("Show details").accessibilityLabel("Show details")
      .popover(isPresented: $showsNotice) {
        ScrollView {
          ChatSessionNotices(model: model, openSettings: openSettings).padding(Self.noticePadding)
        }.frame(width: Self.noticeSize.width, height: Self.noticeSize.height).background(
          theme.paper)
      }
  }

  private var microphoneButton: some View {
    Button {
      if model.isVoiceConversationActive {
        model.muteMicrophone()
      } else {
        Task { await model.startTalk() }
      }
    } label: {
      controlIcon(model.isVoiceConversationActive ? "mic.slash.fill" : "mic.fill")
    }.disabled(!model.isVoiceConversationActive && !model.canCompose)
      .help(
        model.isVoiceConversationActive
          ? String(localized: "Mute") : String(localized: "Start talking")
      )
      .accessibilityLabel(
        model.isVoiceConversationActive
          ? String(localized: "Mute") : String(localized: "Start talking"))
  }

  @ViewBuilder private var playbackButton: some View {
    if model.isWorking {
      Button {
        model.interrupt()
      } label: {
        controlIcon("stop.fill")
      }.help("Stop reply").accessibilityLabel("Stop reply")
    } else if model.canContinueSpeaking {
      Button {
        model.continueSpeaking()
      } label: {
        controlIcon("play.fill")
      }.help("Continue speaking").accessibilityLabel("Continue speaking")
    }
  }

  private func controlIcon(_ name: String) -> some View {
    Image(systemName: name).frame(
      width: SessionHUDMetrics.controlSize, height: SessionHUDMetrics.controlSize)
  }
}
