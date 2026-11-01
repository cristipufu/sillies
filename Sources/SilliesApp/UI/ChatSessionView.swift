import AppKit
import SilliesChat
import SilliesCore
import SwiftUI

enum ChatPresentationMotion { case animated, reduced }

struct ChatSessionView: View {
  @Bindable var model: ChatSession
  let openSettings: (ChatNotice.SettingsDestination) -> Void
  var renderer: String? = nil
  var motion = ChatPresentationMotion.animated
  @State private var registry = RendererRegistry()
  @State private var availabilityRevision = UUID()
  private static let maximumNoticeHeight: CGFloat = 96
  private static let languages = Locale.LanguageCode.isoLanguageCodes.map(\.identifier)
    .filter { $0.count == 2 }.sorted {
      languageName($0).localizedStandardCompare(languageName($1)) == .orderedAscending
    }
  private static func languageName(_ code: String) -> String {
    Locale.current.localizedString(forLanguageCode: code) ?? code
  }

  var body: some View {
    VStack(spacing: 0) {
      header.padding(16)
      Divider().overlay(SilliesTheme.border)
      ChatMessagesView(model: model, motion: motion)
      if model.failure != nil || model.notice != nil || model.hasReachedMessageLimit
        || model.draft.count > ChatContext.maximumMessageCharacters
      {
        ScrollView { notices.padding(.horizontal, 16).padding(.vertical, 8) }
          .scrollBounceBehavior(.basedOnSize).frame(maxHeight: Self.maximumNoticeHeight)
      }
      composer.padding(14).background(SilliesTheme.card)
    }
    .background(SilliesTheme.paper).foregroundStyle(SilliesTheme.ink).tint(SilliesTheme.accent)
    .task(id: availabilityRevision) { await model.refreshAvailability() }
    .onChange(of: model.language) { availabilityRevision = UUID() }
    .onChange(of: model.spokenReplies) { availabilityRevision = UUID() }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      availabilityRevision = UUID()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle().fill(SilliesTheme.accent.opacity(0.13))
        if let renderer {
          CharacterPortrait(renderer: renderer, size: 48, registry: registry)
        } else {
          Image(systemName: "face.smiling.fill").font(.system(size: 30)).foregroundStyle(
            SilliesTheme.accent)
        }
      }.frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: 4) {
        Text(model.companionName).font(.system(size: 22, weight: .bold, design: .rounded))
        HStack(spacing: 5) {
          Circle().fill(
            model.isVoiceConversationActive ? SilliesTheme.success : SilliesTheme.accent
          ).frame(
            width: 6, height: 6)
          Text(model.status).font(.caption).foregroundStyle(SilliesTheme.secondary)
        }
      }
      Spacer(minLength: 4)
      options
      Button {
        model.onFinish?()
      } label: {
        Image(systemName: "checkmark.circle")
      }
      .buttonStyle(.plain).font(.title3).help("Finish & Save conversation")
      .accessibilityLabel("Finish and save conversation")
    }
  }

  private var options: some View {
    Menu {
      Picker("Reply language", selection: $model.language) {
        if !Self.languages.contains(model.language) {
          Text(Self.languageName(model.language)).tag(model.language)
        }
        ForEach(Self.languages, id: \.self) { Text(Self.languageName($0)).tag($0) }
      }.disabled(!model.canCompose)
      Toggle("Spoken replies", isOn: $model.spokenReplies).disabled(!model.canCompose)
      Divider()
      Button("Choose a voice…") { openSettings(.voices) }
      Button("Choose a text model…") { openSettings(.textModels) }
    } label: {
      Image(systemName: "ellipsis.circle").font(.title3)
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Chat options")
    .accessibilityLabel("Chat options")
  }

  private var notices: some View {
    VStack(alignment: .leading, spacing: 8) {
      if model.hasReachedMessageLimit {
        Text("This conversation is full. Finish & Save, then start a new chat.").font(.caption)
      } else if model.draft.count > ChatContext.maximumMessageCharacters {
        Text(
          "This thought is too long to send. Shorten it to \(ChatContext.maximumMessageCharacters) characters; your words are kept here."
        ).font(.caption)
      }
      if let failure = model.failure { SessionFailureNotice(failure: failure) }
      if let notice = model.notice {
        Text(notice.message).font(.caption).foregroundStyle(SilliesTheme.secondary).textSelection(
          .enabled)
        if let destination = notice.settingsDestination {
          Button(
            destination == .textModels
              ? String(localized: "Choose a text model…") : String(localized: "Choose a voice…")
          ) {
            openSettings(destination)
          }.buttonStyle(SoftButtonStyle())
        }
      }
      if model.canRetry {
        Button("Try reply again") { model.retry() }.buttonStyle(SoftButtonStyle())
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private var composer: some View {
    VStack(spacing: 9) {
      if model.isVoiceConversationActive {
        VStack(spacing: 6) {
          Label(model.status, systemImage: "waveform").font(
            .system(.callout, design: .rounded).weight(.semibold)
          )
          .foregroundStyle(SilliesTheme.accent)
          Text(
            model.draft.isEmpty
              ? String(localized: "Speak naturally. You can interrupt a reply.") : model.draft
          )
          .font(.callout).foregroundStyle(SilliesTheme.secondary).lineLimit(3)
          .frame(maxWidth: .infinity, minHeight: 34)
        }.padding(10)
      } else {
        ZStack(alignment: .topLeading) {
          ChatComposer(
            text: $model.draft, isEditable: model.canCompose || model.isWorking, send: model.send
          )
          .frame(height: 68)
          if model.draft.isEmpty {
            Text("Message \(model.companionName)…").font(.system(size: 15))
              .foregroundStyle(SilliesTheme.secondary).padding(.leading, 9).padding(.top, 8)
              .allowsHitTesting(false)
          }
        }.padding(4).background(SilliesTheme.paper, in: RoundedRectangle(cornerRadius: 18))
          .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(SilliesTheme.border))
      }
      HStack {
        if model.isVoiceConversationActive {
          Button("End voice", systemImage: "phone.down.fill") { model.stopVoiceConversation() }
            .buttonStyle(SoftButtonStyle())
          if model.phase == .listening {
            Button("Send now", systemImage: "arrow.up") { model.finishListening() }.buttonStyle(
              .plain)
          }
        } else {
          Button("Voice", systemImage: "mic.fill") { model.startListening() }
            .buttonStyle(SoftButtonStyle()).disabled(!model.canCompose || !model.draft.isEmpty)
            .help("Start a voice conversation with automatic turn-taking")
        }
        Spacer()
        if model.isWorking {
          Button("Stop reply", systemImage: "stop.fill") { model.interrupt() }.buttonStyle(.plain)
        } else if !model.isVoiceConversationActive {
          Button {
            model.send()
          } label: {
            Image(systemName: "arrow.up").font(.headline).frame(width: 20, height: 24)
          }
          .buttonStyle(AccentButtonStyle()).clipShape(Circle()).disabled(!model.canSend)
          .accessibilityLabel("Send message").help("Send · Return")
          .keyboardShortcut(.return, modifiers: .command)
        }
      }
      HStack {
        Label("On your Mac", systemImage: "lock.fill")
        Spacer()
        Text(
          model.isVoiceConversationActive
            ? (model.phase == .preparingMicrophone
              ? String(localized: "Preparing voice conversation…")
              : String(localized: "Microphone on · Echo cancellation"))
            : String(localized: "Return to send · Shift–Return for a new line"))
      }.font(.system(size: 10)).foregroundStyle(SilliesTheme.secondary)
    }
  }
}
