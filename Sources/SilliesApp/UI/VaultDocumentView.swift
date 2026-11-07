import AppKit
import SilliesCore
import SwiftUI

struct VaultDocumentView: View {
  @Environment(\.silliesTheme) private var theme
  let vault: SessionVaultStore
  @Bindable var model: VaultDocumentModel
  let actions: SessionVaultModel
  let workspace: VaultWorkspaceModel
  @FocusState private var titleFocused: Bool
  @FocusState private var tagsFocused: Bool
  @State private var confirmsDeletion = false
  @State private var showsSource = false

  var body: some View {
    if let header = model.header {
      VStack(alignment: .leading, spacing: 0) {
        headerView(header).padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 16)
        if let link = header.metadata.link {
          VaultLinkCard(link: link, image: vault.cachedImage(for: link)).padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        VaultDocumentNotices(header: header, model: model, workspace: workspace)
        if header.metadata.trashedAt != nil {
          HStack {
            Text("This item is in Trash.").foregroundStyle(theme.secondary)
            Spacer()
            Button("Restore") { Task { await model.edit(.restore, recordID: header.id) } }
            Button("Delete permanently…", role: .destructive) { confirmsDeletion = true }
          }.font(.caption).padding(16).background(theme.soft)
        }
        sectionPicker(header)
        Divider().overlay(theme.border)
        if let record = model.speakerRecord {
          VStack(alignment: .leading, spacing: 16) {
            Button("Back to document", systemImage: "chevron.left") { model.hideSpeakers() }
            SpeakerNamingView(record: record) { speaker, name in
              actions.rename(speaker, to: name, in: record)
            }
            Spacer()
          }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.pane == .screenshot {
          VaultScreenshotView(vault: vault, source: header.source)
        } else if model.pane == .files {
          files(header)
        } else {
          readingPane(header)
        }
        if model.playback.duration > 0 {
          VaultRecordingControls(document: model, recordID: header.id)
          VaultInlinePlayback(model: model.playback)
        }
      }
      .onChange(of: titleFocused) { _, focused in if !focused { Task { await model.saveTitle() } } }
      .onChange(of: tagsFocused) { _, focused in if !focused { Task { await model.saveTags() } } }
      .disabled(model.isLoading)
      .confirmationDialog("Delete this item permanently?", isPresented: $confirmsDeletion) {
        Button("Delete permanently", role: .destructive) { vault.remove(id: header.id) }
      } message: {
        Text("Its notes, transcript and attached files will be removed from this Mac.")
      }
    } else if model.isLoading {
      ProgressView("Opening item…").frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let error = model.error {
      ContentUnavailableView {
        Label("Unavailable Vault item", systemImage: "exclamationmark.triangle")
      } description: {
        Text(error).textSelection(.enabled)
      } actions: {
        Button("Try again") { workspace.retrySelection() }
      }
    } else {
      ContentUnavailableView {
        Label("Room for your thoughts", systemImage: "sparkles")
      } description: {
        Text("Choose something from your Vault, or start a fresh note.")
      }
    }
  }

  private func headerView(_ header: VaultDocumentHeader) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: header.symbol).foregroundStyle(theme.accent)
        Text(header.source.createdAt.formatted(date: .abbreviated, time: .shortened))
          .foregroundStyle(theme.secondary)
          .font(.system(size: 11.5))
        Spacer()
        Button {
          showsSource.toggle()
        } label: {
          Image(systemName: "info.circle")
        }
        .buttonStyle(.plain).help("Source & processing")
        .popover(isPresented: $showsSource) { VaultSourceDetails(source: header.source) }
        if header.source.isProtected {
          Image(systemName: "lock.fill").foregroundStyle(theme.secondary).help(
            "Protected from automatic deletion")
        }
        Button {
          Task {
            await model.edit(header.metadata.isStarred ? .unstar : .star, recordID: header.id)
          }
        } label: {
          Image(systemName: header.metadata.isStarred ? "star.fill" : "star").foregroundStyle(
            theme.accent)
        }.buttonStyle(.plain).help("Star and keep this item")
        Menu {
          if header.source.isProtected {
            Button("Remove protection") { actions.removeProtection(id: header.id) }
          } else {
            Button("Keep this item") { actions.keep(id: header.id) }
          }
          if header.metadata.kind == .capture {
            Button("Regenerate notes") { actions.regenerateNotes(id: header.id) }.disabled(
              header.source.summaryPending)
          }
          if model.sections.contains(.transcript) {
            Button("Name the speakers") { Task { await model.showSpeakers() } }
            Button("Open transcript in separate window") {
              Task { await actions.popOutTranscript(id: header.id) }
            }
          }
          if header.source.imageFilename != nil {
            Button("Copy Image") { vault.copyImage(for: header.source) }
            Button(
              header.source.screenshotTextState == .failed
                ? String(localized: "Retry screenshot text recognition")
                : String(localized: "Recognize text again")
            ) { actions.retryScreenshotText(header.id) }
            .disabled(header.source.screenshotTextState == .pending || model.editor.isDirty)
          }
          if let link = header.metadata.link {
            Button("Copy link") { vault.copyText(link.url.absoluteString) }
            Button("Refresh preview") {
              var pending = link
              pending.previewState = .pending
              Task { await model.edit(.linkPreview(pending), recordID: header.id) }
            }
          }
          if let discussion = actions.discussion {
            Menu("Discuss with…") {
              ForEach(discussion.companions, id: \.id) { companion in
                Button(companion.name) { actions.discuss(header.id, with: companion) }
              }
            }
          }
          Menu("Add to collection") {
            ForEach(workspace.collections) { collection in
              Button {
                Task {
                  await model.edit(
                    header.metadata.collectionIDs.contains(collection.id)
                      ? .removeFromCollection(collection.id) : .addToCollection(collection.id),
                    recordID: header.id)
                }
              } label: {
                if header.metadata.collectionIDs.contains(collection.id) {
                  Label(collection.name, systemImage: "checkmark")
                } else {
                  Text(collection.name)
                }
              }
            }
          }
          Button("Copy visible text") { vault.copyText(model.editor.text) }
            .disabled(model.visibleTextLocation == nil)
          if header.metadata.kind == .capture, let pasteBack = actions.pasteBack,
            pasteBack.destination != nil
          {
            Button(pasteBack.actionTitle) { actions.paste(id: header.id) }
              .disabled(actions.isPasting || pasteBack.isPasting)
          }
          Button("Copy selection") { vault.copyText(model.editor.selectedText) }.disabled(
            model.editor.selectedText.isEmpty || model.visibleTextLocation == nil)
          Button("Export selection…") { actions.exportSelectedText() }.disabled(
            !actions.canExport || model.editor.selectedText.isEmpty
              || model.visibleTextLocation == nil)
          Button("Quote selection into notes…") { Task { await workspace.quoteSelection() } }
            .disabled(
              model.editor.selectedText.isEmpty || model.visibleTextLocation == nil)
          Button("Export Markdown & attachments…") { actions.exportIDs([header.id]) }.disabled(
            !actions.canExport)
          if header.metadata.trashedAt == nil {
            Button("Move to Trash", role: .destructive) {
              Task { await model.moveToTrash(recordID: header.id) }
            }
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }.menuStyle(.borderlessButton).frame(width: 20)
      }
      TextField("Title", text: $model.title).textFieldStyle(.plain).font(
        .system(size: 24, weight: .bold, design: .rounded)
      )
      .focused($titleFocused).onSubmit { titleFocused = false }
      .disabled(header.metadata.trashedAt != nil)
      HStack(spacing: 7) {
        Image(systemName: "number").foregroundStyle(theme.secondary)
        TextField("Add tags, separated by commas", text: $model.tags).textFieldStyle(.plain).font(
          .system(size: 12)
        )
        .focused($tagsFocused).onSubmit { tagsFocused = false }
        .disabled(header.metadata.trashedAt != nil)
      }
    }
  }

  private func sectionPicker(_ header: VaultDocumentHeader) -> some View {
    HStack {
      Picker(
        "Section",
        selection: Binding(
          get: { model.pane }, set: { pane in Task { await model.selectPane(pane) } })
      ) {
        ForEach(model.panes, id: \.self) { pane in Text(pane.title).tag(pane) }
      }.labelsHidden().fixedSize()
      Spacer()
      if model.editor.isSaving || model.metadata.isSaving { ProgressView().controlSize(.mini) }
      if header.source.summaryPending { ProgressView("Preparing local notes…").controlSize(.mini) }
      Text(
        model.editor.isDirty || model.metadata.isDirty
          ? String(localized: "Unsaved changes") : String(localized: "Saved on this Mac")
      )
      .font(.system(size: 10.5)).foregroundStyle(theme.secondary)
    }.font(.system(size: 12)).padding(.horizontal, 24).padding(.vertical, 10)
  }

  private func readingPane(_ header: VaultDocumentHeader) -> some View {
    VStack(spacing: 0) {
      if model.section == .notes, header.metadata.trashedAt == nil {
        HStack(spacing: 16) {
          ForEach(VaultTextFormatting.allCases) { action in
            Button {
              model.editor.format(action)
            } label: {
              Image(systemName: action.symbol)
            }
            .buttonStyle(.plain).help(action.title).accessibilityLabel(action.title)
          }
          Spacer()
          Menu {
            Button("Copy selection") { vault.copyText(model.editor.selectedText) }
            Button("Quote selection into notes…") { Task { await workspace.quoteSelection() } }
          } label: {
            Image(systemName: "text.badge.plus")
          }
          .menuStyle(.borderlessButton).frame(width: 20).disabled(model.editor.selectedText.isEmpty)
        }.font(.system(size: 12)).padding(.horizontal, 24).padding(.vertical, 10)
      }
      if model.editor.recoveredDraft {
        HStack {
          Text("A recovered draft is ready to review.").font(.caption)
          Button("Save draft") { Task { await model.editor.retrySavingDraft() } }
          Button("Discard draft") { Task { await model.editor.discardRecoveredDraft() } }
          Button("Save as new note") { Task { await workspace.recoverDraftAsNote() } }
        }.padding(12).background(theme.soft)
          .disabled(model.editor.isRecovering || model.editor.isSaving)
      }
      if model.editor.isLoading { ProgressView().controlSize(.small).padding(8) }
      if model.section == .transcript, model.playback.duration > 0,
        let time = model.editor.blocks.first?.startSeconds
      {
        HStack {
          Button("Play from \(SessionRecord.formatDuration(time))", systemImage: "play.circle") {
            model.playback.play(from: time)
          }.buttonStyle(.plain)
          Spacer()
          Menu("Timestamps on this page") {
            ForEach(model.editor.blocks.filter { $0.startSeconds != nil }) { block in
              if let time = block.startSeconds {
                Button(SessionRecord.formatDuration(time)) {
                  model.playback.play(from: time)
                  model.editor.reveal(block.location)
                }
              }
            }
          }.menuStyle(.borderlessButton).fixedSize()
        }.font(.caption).padding(.horizontal, 24).padding(.vertical, 8)
      }
      ZStack(alignment: .topLeading) {
        if model.editor.text.isEmpty && model.section == .notes {
          Text("Your thoughts belong here. Write a note, a question, or what to do next.")
            .font(.system(size: 14)).foregroundStyle(theme.secondary.opacity(0.7)).padding(24)
            .allowsHitTesting(false)
        }
        VaultNativeTextEditor(
          model: model.editor, isPresented: workspace.isPresented,
          allowsEditing: header.metadata.trashedAt == nil && !model.isLoading
            && !model.editor.isLoading,
          openSource: { reference in Task { await workspace.openSource(reference) } })
      }
      if model.editor.previousOrdinal != nil || model.editor.nextOrdinal != nil {
        HStack {
          if let earlier = model.editor.previousOrdinal {
            Button("Earlier text", systemImage: "chevron.up") {
              Task { await model.editor.move(to: earlier) }
            }
          }
          Spacer()
          if let next = model.editor.nextOrdinal {
            Button("Continue reading", systemImage: "chevron.down") {
              Task { await model.editor.move(to: next) }
            }
          }
        }.font(.caption).padding(14)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func files(_ header: VaultDocumentHeader) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VaultFileReferencesView(model: model.externalFiles, relink: actions.relink)
        if let image = vault.cachedImage(for: header.source) {
          Image(nsImage: image).resizable().scaledToFit()
        }
        if let imageURL = vault.imageURL(for: header.source) {
          Button("Show image file", systemImage: "photo") {
            NSWorkspace.shared.activateFileViewerSelecting([imageURL])
          }
        }
        if let audioURL = vault.audioURL(for: header.source) {
          Button("Show audio file", systemImage: "waveform") {
            NSWorkspace.shared.activateFileViewerSelecting([audioURL])
          }
        }
      }.padding(24)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .task(id: header.id) { await model.externalFiles.load(id: header.id) }
  }
}
