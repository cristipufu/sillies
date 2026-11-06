import AppKit
import SilliesChat
import SilliesCore
import SwiftUI

enum ChatPresentationMotion { case animated, reduced }

struct ChatSessionView: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var model: ChatSession
  let openSettings: (ChatNotice.SettingsDestination) -> Void
  let close: () -> Void
  var renderer: String? = nil
  var motion = ChatPresentationMotion.animated
  var vault: ChatVaultPresentation? = nil
  var exportConversation: () -> Void = {}
  var readingPreference: Binding<ChatReadingSize>? = nil
  @State var navigation = ChatWindowNavigation()
  @State private var showsStarters = false
  @State private var readingSize = ChatReadingSize.standard
  @State private var composerFocus: UUID?
  @State private var confirmsClear = false
  @State private var registry = RendererRegistry()
  @State private var availabilityRevision = UUID()
  private static let starterWidth: CGFloat = 290
  private static let starterInset: CGFloat = 16
  private static let searchButtonSize = CGSize(width: 24, height: 28)
  private static let languages = Locale.LanguageCode.isoLanguageCodes.map(\.identifier)
    .filter { $0.count == 2 }.sorted {
      languageName($0).localizedStandardCompare(languageName($1)) == .orderedAscending
    }
  private static func languageName(_ code: String) -> String {
    Locale.current.localizedString(forLanguageCode: code) ?? code
  }

  private var showsConversation: Bool {
    navigation.page == .conversation && !model.memoryEditor.isPresented
  }

  var body: some View {
    ZStack {
      conversation
        .opacity(showsConversation ? 1 : 0)
        .allowsHitTesting(showsConversation)
        .disabled(!showsConversation)
        .accessibilityHidden(!showsConversation)
        .environment(\.chatTextPresentation, showsConversation ? .visible : .concealed)
      if !showsConversation { auxiliaryPage }
    }
    .environment(\.chatReadingSize, readingPreference?.wrappedValue ?? readingSize)
    .background(theme.paper).foregroundStyle(theme.ink).tint(theme.accent)
    .task(id: availabilityRevision) {
      await model.restoreHistory()
      // Talk owns its startup checks. A transcript refresh must not supersede that activation.
      guard model.mode == .chat else { return }
      await model.refreshAvailability()
    }
    .onChange(of: model.language) { availabilityRevision = UUID() }
    .onChange(of: model.spokenReplies) { availabilityRevision = UUID() }
    .onChange(of: showsConversation) { _, visible in
      if visible { composerFocus = UUID() }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      availabilityRevision = UUID()
    }
  }

  @ViewBuilder private var auxiliaryPage: some View {
    if model.memoryEditor.isPresented {
      ChatMemoryEditorView(editor: model.memoryEditor)
    } else {
      switch navigation.page {
      case .conversation: EmptyView()
      case .memories:
        ConversationMemoriesView(
          model: model, back: returnToConversation,
          openSettings: { openSettings(.companionProfile) })
      case .search:
        ConversationSearchView(browser: model.browser, back: returnToConversation)
      case .vault:
        if let vault {
          ChatVaultPicker(
            store: vault.store, selection: model.selectedRecords, back: returnToConversation)
        }
      }
    }
  }

  private func returnToConversation() {
    navigation.show(.conversation)
  }

  private var conversation: some View {
    VStack(spacing: 0) {
      header.padding(12)
      Divider().overlay(theme.border)
      ChatMessagesView(
        model: model, motion: motion, vault: vault, focusComposer: { composerFocus = UUID() })
      if model.failure != nil || model.notice != nil || model.history.failure != nil
        || model.draft.count > ChatContext.maximumMessageCharacters
        || model.export.notice != nil || model.export.isExporting
        || model.canRetry || model.canContinueSpeaking
      {
        ChatNoticeViewport(model: model, openSettings: openSettings)
      }
      if model.mode == .chat {
        if let vault {
          ChatContextStrip(selection: model.selectedRecords, openRecord: vault.openRecord)
        }
        ChatComposerField(
          model: model, focusRequest: composerFocus,
          addContext: vault != nil && model.selectedRecords.isAvailable
            ? { navigation.show(.vault) } : nil
        ).padding(16)
      }
    }
    .dropDestination(for: VaultRecordTransfer.self) { items, _ in
      guard showsConversation, model.mode == .chat, model.selectedRecords.canAdd else {
        return false
      }
      var accepted = false
      for item in items.prefix(ConversationRecordSelection.maximumRecords) {
        if model.selectedRecords.add(item.id) { accepted = true }
      }
      return accepted
    }
    .popover(isPresented: $showsStarters) {
      ConversationStartersView(model: model) {
        showsStarters = false
        composerFocus = UUID()
      }.padding(Self.starterInset).frame(width: Self.starterWidth).background(theme.paper)
        .foregroundStyle(theme.ink)
    }
    .confirmationDialog("Clear this conversation and its memories?", isPresented: $confirmsClear) {
      Button("Clear conversation", role: .destructive) { Task { await model.clearConversation() } }
    } message: {
      Text(
        "Delete this companion’s messages, draft and learned memories. Keep pinned facts and preferences."
      )
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
          .lineLimit(1).help(model.companionName)
        HStack(spacing: 5) {
          Circle().fill(
            model.isVoiceConversationActive ? theme.success : theme.accent
          ).frame(
            width: 6, height: 6)
          Text(model.status).font(.caption).foregroundStyle(theme.secondary).lineLimit(2)
        }
      }
      Spacer(minLength: 4)
      Button {
        navigation.show(.search)
      } label: {
        Image(systemName: "magnifyingglass").frame(
          width: Self.searchButtonSize.width, height: Self.searchButtonSize.height)
      }.buttonStyle(.plain).help("Search conversation").accessibilityLabel("Search conversation")
        .keyboardShortcut("f", modifiers: .command)
      options
      Button(action: close) {
        Image(systemName: "xmark")
      }
      .buttonStyle(.plain).font(.title3)
      .help(
        model.mode == .talk ? String(localized: "Dismiss") : String(localized: "Close conversation")
      )
      .accessibilityLabel(
        model.mode == .talk ? String(localized: "Dismiss") : String(localized: "Close conversation")
      )
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
      Button("Search conversation…") { navigation.show(.search) }
      if model.mode == .chat { Button("Conversation ideas…") { showsStarters = true } }
      Button("Export conversation…", action: exportConversation).disabled(
        !model.export.isAvailable || model.export.isExporting)
      Button("Memories…") { navigation.show(.memories) }
      Button("Companion settings…") { openSettings(.companionProfile) }
      Button("Clear conversation…", role: .destructive) { confirmsClear = true }.disabled(
        !model.canCompose)
      Divider()
      Picker("Message size", selection: readingPreference ?? $readingSize) {
        ForEach(ChatReadingSize.allCases, id: \.self) { size in Text(size.title).tag(size) }
      }
      Button("Choose a voice…") { openSettings(.voices) }
      Button("Choose a text model…") { openSettings(.textModels) }
    } label: {
      Image(systemName: "ellipsis.circle").font(.title3)
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Chat options")
    .accessibilityLabel("Chat options")
  }

}
