import AppKit
import SilliesChat
import SilliesCore
import SwiftUI

struct ChatSessionView: View {
  @Bindable var model: ChatSession
  let openSettings: (ChatNotice.SettingsDestination) -> Void
  @State private var availabilityRevision = UUID()
  @State private var followsLive = true
  @FocusState private var composerFocused: Bool
  private static let maximumNoticeHeight: CGFloat = 100
  private static let languages = Locale.LanguageCode.isoLanguageCodes.map(\.identifier)
    .filter { $0.count == 2 }
    .sorted {
      languageName($0).localizedStandardCompare(languageName($1)) == .orderedAscending
    }

  private static func languageName(_ code: String) -> String {
    Locale.current.localizedString(forLanguageCode: code) ?? code
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header.fixedSize(horizontal: false, vertical: true)
      HStack {
        Picker("Reply language", selection: $model.language) {
          if !Self.languages.contains(model.language) {
            Text(Self.languageName(model.language)).tag(model.language)
          }
          ForEach(Self.languages, id: \.self) { language in
            Text(Self.languageName(language)).tag(language)
          }
        }.frame(maxWidth: 240).disabled(!model.canCompose)
          .help("Language support depends on your chosen text, speech and voice models.")
        Spacer()
        Toggle("Spoken replies", isOn: $model.spokenReplies).toggleStyle(.checkbox)
          .disabled(!model.canCompose)
      }.font(.callout)
      SessionTranscriptCard(
        text: model.transcript, isFinished: model.phase == .finished, followsLive: $followsLive,
        title: "Conversation"
      ) {
        VStack(spacing: 12) {
          Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 30)).foregroundStyle(
            SilliesTheme.accent)
          Text("A little company, just for you.").font(.headline)
          Text("Type a thought or tap Speak to use the microphone.")
            .font(.callout).foregroundStyle(SilliesTheme.secondary)
        }.frame(maxWidth: .infinity).padding(24)
      }
      if model.failure != nil || model.notice != nil {
        ViewThatFits(in: .vertical) {
          notices
          ScrollView { notices }.scrollBounceBehavior(.basedOnSize)
        }
        .frame(minHeight: 0, maxHeight: Self.maximumNoticeHeight)
      }
      if model.phase != .finished { composer }
      if model.hasReachedMessageLimit {
        Text("This conversation is full. Finish & Save, then start a new Chat.")
          .font(.caption).foregroundStyle(SilliesTheme.secondary)
      }
      HStack {
        Label("Private · On your Mac", systemImage: "lock.shield").font(.caption)
        Spacer()
        Text("AI replies can be mistaken.").font(.caption)
      }.foregroundStyle(SilliesTheme.secondary)
    }.padding(20).background(SilliesTheme.paper).foregroundStyle(SilliesTheme.ink).tint(
      SilliesTheme.accent
    )
    .onAppear { composerFocused = true }
    .task(id: availabilityRevision) { await model.refreshAvailability() }
    .onChange(of: model.language) { availabilityRevision = UUID() }
    .onChange(of: model.spokenReplies) { availabilityRevision = UUID() }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      availabilityRevision = UUID()
    }
  }

  private var notices: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let failure = model.failure { SessionFailureNotice(failure: failure) }
      if let notice = model.notice {
        HStack(alignment: .top) {
          Text(notice.message).font(.caption).foregroundStyle(SilliesTheme.secondary)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 8)
          if let destination = notice.settingsDestination {
            Button(destination == .textModels ? "Choose a text model…" : "Choose a voice…") {
              openSettings(destination)
            }.buttonStyle(SoftButtonStyle())
          }
        }
      }
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: CompanionSkillKind.chat.symbolName).font(.title2).foregroundStyle(
        SilliesTheme.accent)
      VStack(alignment: .leading, spacing: 4) {
        Text("Chat with \(model.companionName)").font(
          .system(size: 23, weight: .bold, design: .rounded))
        Text(model.status).font(.callout).foregroundStyle(SilliesTheme.secondary)
      }
      Spacer()
      if model.isWorking {
        Button("Stop reply", systemImage: "stop.fill") { model.interrupt() }.buttonStyle(
          SoftButtonStyle())
      }
      if model.phase != .finished {
        Button("Finish & Save") { model.onFinish?() }.buttonStyle(SoftButtonStyle())
      }
    }
  }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("What’s on your mind?", text: $model.draft, axis: .vertical)
        .lineLimit(2...4).textFieldStyle(.plain).padding(12)
        .background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SilliesTheme.border))
        .focused($composerFocused).disabled(!model.canCompose)
      HStack {
        if model.isRecording {
          Button("Done speaking", systemImage: "stop.circle.fill") { model.finishListening() }
            .buttonStyle(SoftButtonStyle())
        } else {
          Button("Speak", systemImage: "mic.fill") { model.startListening() }
            .buttonStyle(SoftButtonStyle()).disabled(!model.canCompose || !model.draft.isEmpty)
        }
        if model.canRetry {
          Button("Retry reply") { model.retry() }.buttonStyle(SoftButtonStyle())
        }
        Spacer()
        if model.draft.count > ChatContext.maximumMessageCharacters {
          Text("Keep each message under \(ChatContext.maximumMessageCharacters) characters.").font(
            .caption)
        }
        Button("Send", systemImage: "arrow.up") { model.send() }
          .buttonStyle(.borderedProminent).disabled(!model.canSend)
          .keyboardShortcut(.return, modifiers: .command)
      }
    }
  }
}
