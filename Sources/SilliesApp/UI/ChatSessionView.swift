import AppKit
import SilliesChat
import SilliesCore
import SwiftUI

enum ChatPresentationMotion { case animated, reduced }

struct ChatSessionView: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var model: ChatSession
  let openSettings: (ChatNotice.SettingsDestination) -> Void
  var renderer: String? = nil
  var motion = ChatPresentationMotion.animated
  var vault: ChatVaultPresentation? = nil
  @State private var showsMemories = false
  @State private var showsSearch = false
  @State private var confirmsClear = false
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
      header.padding(12)
      Divider().overlay(theme.border)
      if model.mode == .chat {
        ChatMessagesView(model: model, motion: motion, vault: vault)
      } else {
        TalkCaptionsView(model: model)
      }
      if model.failure != nil || model.notice != nil || model.history.failure != nil
        || model.draft.count > ChatContext.maximumMessageCharacters
      {
        ScrollView { notices.padding(.horizontal, 16).padding(.vertical, 8) }
          .scrollBounceBehavior(.basedOnSize).frame(maxHeight: Self.maximumNoticeHeight)
      }
      composer.padding(14).background(theme.card)
    }
    .background(theme.paper).foregroundStyle(theme.ink).tint(theme.accent)
    .task(id: availabilityRevision) {
      await model.restoreHistory()
      await model.refreshAvailability()
    }
    .sheet(isPresented: $showsMemories) { ConversationMemoriesView(model: model) }
    .sheet(isPresented: $showsSearch) { ConversationSearchView(browser: model.browser) }
    .confirmationDialog("Clear this conversation and its memories?", isPresented: $confirmsClear) {
      Button("Clear conversation", role: .destructive) { Task { await model.clearConversation() } }
    } message: {
      Text("Saved messages and memories for this companion will be deleted from this Mac.")
    }
    .onChange(of: model.language) { availabilityRevision = UUID() }
    .onChange(of: model.spokenReplies) { availabilityRevision = UUID() }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      availabilityRevision = UUID()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle().fill(theme.accent.opacity(0.13))
        if let renderer {
          CharacterPortrait(renderer: renderer, size: 36, registry: registry)
        } else {
          Image(systemName: "face.smiling.fill").font(.system(size: 30)).foregroundStyle(
            theme.accent)
        }
      }.frame(width: 40, height: 40)
      VStack(alignment: .leading, spacing: 4) {
        Text(model.companionName).font(.system(size: 19, weight: .bold, design: .rounded))
        HStack(spacing: 5) {
          Circle().fill(
            model.isVoiceConversationActive ? theme.success : theme.accent
          ).frame(
            width: 6, height: 6)
          Text(model.status).font(.caption).foregroundStyle(theme.secondary)
        }
      }
      Spacer(minLength: 4)
      options
      Button {
        model.onFinish?()
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.plain).font(.title3).help("Close conversation")
      .accessibilityLabel("Close conversation")
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
      Button("Chat") { model.showChat() }
      Button("Talk") { Task { await model.startTalk() } }.disabled(!model.canCompose)
      Divider()
      Button("Search conversation…") { showsSearch = true }
      Button("Memories…") { showsMemories = true }
      Button("Clear conversation…", role: .destructive) { confirmsClear = true }.disabled(
        !model.canCompose)
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
      if model.draft.count > ChatContext.maximumMessageCharacters {
        Text(
          "This thought is too long to send. Shorten it to \(ChatContext.maximumMessageCharacters) characters; your words are kept here."
        ).font(.caption)
      }
      if let error = model.history.failure {
        Text(error).font(.caption).textSelection(.enabled)
        Button("Retry saving") { Task { await model.retrySaving() } }.buttonStyle(SoftButtonStyle())
      }
      if let failure = model.failure { SessionFailureNotice(failure: failure) }
      if let notice = model.notice {
        Text(notice.message).font(.caption).foregroundStyle(theme.secondary).textSelection(
          .enabled)
      }
      if let destination = model.recoverySettingsDestination {
        Button(
          destination == .textModels
            ? String(localized: "Choose a text model…") : String(localized: "Choose a voice…")
        ) {
          openSettings(destination)
        }.buttonStyle(SoftButtonStyle())
      }
      if model.canRetry {
        Button("Try reply again") { model.retry() }.buttonStyle(SoftButtonStyle())
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private var composer: some View {
    if model.mode == .talk {
      VStack(spacing: 10) {
        Text(
          model.draft.isEmpty
            ? String(localized: "Speak naturally. You can interrupt a reply.") : model.draft
        )
        .font(.callout).foregroundStyle(theme.secondary).lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        HStack {
          if model.isVoiceConversationActive {
            Button("Mute", systemImage: "mic.slash.fill") { model.muteMicrophone() }
            Button("End voice", systemImage: "phone.down.fill") { model.stopVoiceConversation() }
          } else {
            Button("Start talking", systemImage: "mic.fill") { Task { await model.startTalk() } }
              .disabled(!model.canCompose)
          }
          Spacer()
          if model.isWorking {
            Button("Stop reply", systemImage: "stop.fill") { model.interrupt() }
          }
        }.buttonStyle(SoftButtonStyle())
      }
    } else {
      HStack(alignment: .bottom, spacing: 10) {
        ZStack(alignment: .topLeading) {
          ChatComposer(
            text: $model.draft,
            isEditable: model.history.isLoaded && model.phase != .finished, send: model.send
          )
          .frame(height: 44)
          if model.draft.isEmpty {
            Text("Message \(model.companionName)…").font(.system(size: 15))
              .foregroundStyle(theme.secondary).padding(.leading, 9).padding(.top, 8)
              .allowsHitTesting(false)
          }
        }.padding(4).background(theme.paper, in: RoundedRectangle(cornerRadius: 18))
          .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(theme.border))
        if model.isWorking {
          Button("Stop reply", systemImage: "stop.fill") { model.interrupt() }
            .labelStyle(.iconOnly).buttonStyle(SoftButtonStyle())
        } else {
          Button {
            model.send()
          } label: {
            Image(systemName: "arrow.up").font(.headline).frame(width: 20, height: 24)
          }.buttonStyle(AccentButtonStyle()).clipShape(Circle()).disabled(!model.canSend)
            .accessibilityLabel("Send message").help("Send · Return")
            .keyboardShortcut(.return, modifiers: .command)
        }
      }.help("Return to send · Shift–Return for a new line")
    }
  }
}
