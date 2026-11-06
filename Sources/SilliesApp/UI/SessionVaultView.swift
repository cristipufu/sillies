import AppKit
import SilliesCore
import SwiftUI

struct SessionVaultView: View {
  @Environment(\.silliesTheme) private var theme
  let vault: SessionVaultStore
  let conversations: VaultConversationsModel?
  @Bindable var model: SessionVaultModel
  @Bindable var navigation: VaultNavigation
  @FocusState private var searchFocused: Bool
  private static let noticeInset: CGFloat = 12

  var body: some View {
    let records = model.filteredRecords
    let current = model.selectedHeader(in: records)
    VStack(spacing: 0) {
      if let failure = model.discussionFailure {
        HStack(alignment: .top) {
          SessionFailureNotice(failure: failure)
          Button {
            model.dismissDiscussionFailure()
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.plain).accessibilityLabel("Dismiss")
        }.padding(Self.noticeInset)
      }
      if conversations != nil {
        Picker("Library", selection: $navigation.section) {
          Text("Vault").tag(VaultNavigation.Section.captures)
          Text("Conversations").tag(VaultNavigation.Section.conversations)
        }.pickerStyle(.segmented).frame(maxWidth: 300).padding(12)
        Divider().overlay(theme.border)
      }
      ZStack {
        HStack(spacing: 0) {
          sidebar(records: records, selected: current)
          Divider().overlay(theme.border)
          SessionVaultDetailView(
            vault: vault, model: model, record: model.visibleDetail,
            isVisible: navigation.section == .captures && model.isPresented)
        }
        .opacity(navigation.section == .captures ? 1 : 0)
        .allowsHitTesting(navigation.section == .captures)
        .disabled(navigation.section != .captures || !model.isPresented)
        .accessibilityHidden(navigation.section != .captures)
        if let conversations {
          VaultConversationsView(
            model: conversations,
            isPresented: navigation.section == .conversations && model.isPresented
          )
          .opacity(navigation.section == .conversations ? 1 : 0)
          .allowsHitTesting(navigation.section == .conversations)
          .disabled(navigation.section != .conversations || !model.isPresented)
          .accessibilityHidden(navigation.section != .conversations)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.paper)
    .foregroundStyle(theme.ink)
    .onChange(of: navigation.section) { _, _ in searchFocused = false }
    .task(id: model.isPresented ? model.searchIdentity : nil) { await model.refreshSearch() }
    .task(id: model.isPresented ? model.detailIdentity : nil) { await model.loadSelection() }
    .sheet(item: $navigation.editor) { editor in
      switch editor {
      case .stash: StashComposerView { model.saveStash([$0]) }
      case .retention: VaultRetentionView(vault: vault)
      }
    }
  }

  private func sidebar(records: [SessionRecordHeader], selected: SessionRecordHeader?) -> some View
  {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(theme.accent.opacity(0.14))
            .frame(width: 34, height: 34)
          Image(systemName: "archivebox.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(theme.accent)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text("Session Vault")
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .tracking(-0.3)
          Text("Captures, transcripts & stashes")
            .font(.system(size: 11))
            .foregroundStyle(theme.secondary)
        }
        Spacer(minLength: 4)
        Text("\(records.count)")
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .monospacedDigit()
          .padding(.horizontal, 9)
          .padding(.vertical, 3.5)
          .background(theme.soft, in: Capsule())
          .foregroundStyle(theme.secondary)
      }

      // Search field
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(theme.secondary)
        TextField(
          "Search transcripts, OCR, stashes…",
          text: Binding(get: { model.searchQuery }, set: { model.searchQuery = $0 })
        )
        .textFieldStyle(.plain)
        .focused($searchFocused)
        .font(.system(size: 12.5))
        if !model.searchQuery.isEmpty {
          Button {
            model.searchQuery = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 12))
              .foregroundStyle(theme.secondary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 11)
      .frame(height: 34)
      .background(theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(theme.border, lineWidth: 0.8))

      HStack {
        Button("Add text / link", systemImage: "plus") { navigation.editor = .stash }
        Spacer()
        Button("Save Clipboard", systemImage: "clipboard") {
          model.saveStash(StashPasteboard.items(from: .general))
        }
      }.font(.system(size: 11, weight: .medium))

      HStack {
        Picker(
          "Show",
          selection: Binding(get: { model.selectedFilter }, set: { model.selectedFilter = $0 })
        ) {
          Text("Everything").tag(Optional<CompanionSkillKind>.none)
          ForEach(
            CompanionSkillKind.allCases.filter { kind in
              CompanionSkillKind.radialSkills.contains(kind) || kind == .stash
                || vault.records.contains { $0.kind == kind }
            }
          ) { kind in Text(kind.title).tag(Optional(kind)) }
        }
        if model.lastStashID != nil {
          Button("Undo save") { model.undoStash() }
        }
      }.font(.caption)

      HStack {
        Button("Retention…") { navigation.editor = .retention }
        Spacer()
        Button("Export all…") { model.exportAll() }.disabled(
          vault.recordCount == 0 || !model.canExport)
      }.font(.caption)

      if let error = vault.persistenceError {
        Text(error).font(.caption).foregroundStyle(theme.warning)
        Button("Retry saving") { vault.retrySaving() }
      }

      if model.isSearching {
        ProgressView(
          model.searchQuery.isEmpty
            ? String(localized: "Loading sessions…") : String(localized: "Searching…")
        ).font(.caption)
      }
      if let error = model.searchError {
        Text(error).font(.caption).foregroundStyle(theme.danger)
      }
      if records.isEmpty {
        emptySidebarState
      } else {
        ScrollView {
          LazyVStack(spacing: 9) {
            ForEach(model.keywordRecords) { record in
              recordRow(record, isSelected: selected?.id == record.id)
            }
            if model.hasMoreResults { Button("Show more") { model.showMore() } }
            if !model.relatedRecords.isEmpty {
              Text("Related by meaning").font(.caption).foregroundStyle(theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
              ForEach(model.relatedRecords) { record in
                recordRow(record, isSelected: selected?.id == record.id)
              }
            }
          }
          .padding(.vertical, 3)
          .padding(.horizontal, 1)
        }
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 18)
    .frame(width: 332)
  }

  private var emptySidebarState: some View {
    VStack(spacing: 12) {
      Spacer()
      ZStack {
        Circle()
          .fill(theme.soft)
          .frame(width: 52, height: 52)
        Image(systemName: "sparkles.rectangle.stack")
          .font(.system(size: 21, weight: .medium))
          .foregroundStyle(theme.secondary)
      }
      Text(
        model.searchQuery.isEmpty && model.selectedFilter == nil
          ? String(localized: "No sessions saved yet") : String(localized: "No matching sessions")
      )
      .font(.system(size: 14, weight: .bold, design: .rounded))
      Text(
        "Drag a companion onto a window to choose a skill. Record from the menu bar, or add text and links here to Pocket Stash."
      )
      .font(.system(size: 11.5))
      .foregroundStyle(theme.secondary)
      .multilineTextAlignment(.center)
      .lineSpacing(2.5)
      .padding(.horizontal, 16)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private func recordRow(_ record: SessionRecordHeader, isSelected: Bool) -> some View {
    Button {
      model.selectedRecordID = record.id
    } label: {
      HStack(alignment: .top, spacing: 11) {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? theme.accent : theme.accent.opacity(0.12))
            .frame(width: 32, height: 32)
          Image(systemName: record.kind.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isSelected ? theme.onAccent : theme.accent)
        }

        VStack(alignment: .leading, spacing: 5) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(record.appName)
              .font(.system(size: 13, weight: .bold, design: .rounded))
              .foregroundStyle(theme.ink)
              .lineLimit(1)
            Spacer(minLength: 4)
            Text(record.createdAt.formatted(date: .omitted, time: .shortened))
              .font(.system(size: 10, weight: .medium))
              .monospacedDigit()
              .foregroundStyle(theme.secondary)
          }

          if let title = record.windowTitle, !title.isEmpty, title != record.appName {
            Text(title)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(theme.secondary)
              .lineLimit(1)
          }

          Text(cleanPreviewText(for: record))
            .font(.system(size: 11))
            .foregroundStyle(theme.ink.opacity(0.80))
            .lineSpacing(1.5)
            .lineLimit(2)
            .multilineTextAlignment(.leading)

          HStack(spacing: 6) {
            Text(record.kind.shortTitle)
              .font(.system(size: 9.5, weight: .bold, design: .rounded))
              .foregroundStyle(theme.accent)
            Text("· \(record.characterName)")
              .font(.system(size: 9.5, weight: .medium, design: .rounded))
              .foregroundStyle(theme.secondary)
            if record.durationSeconds >= 1 {
              Text("· \(SessionRecord.formatDuration(record.durationSeconds))")
                .font(.system(size: 9.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.secondary)
            }
            if record.kind == .stash && record.stashItemCount > 0 {
              Text(
                String(localized: "· \(record.stashItemCount) items", comment: "plural")
              )
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(theme.secondary)
            }
            if record.imageFilename != nil {
              Spacer()
              Image(systemName: "photo")
                .font(.system(size: 9.5))
                .foregroundStyle(theme.secondary)
            }
          }
          .padding(.top, 1)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        isSelected ? theme.accent.opacity(0.10) : theme.card,
        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(
          isSelected ? theme.accent : theme.border.opacity(0.80),
          lineWidth: isSelected ? 1.4 : 0.75))
    }
    .buttonStyle(.plain)
    .draggable(VaultRecordTransfer(id: record.id))
    .contextMenu {
      if let discussion = model.discussion {
        Menu("Discuss with…") {
          ForEach(discussion.companions, id: \.id) { companion in
            Button(companion.name) { model.discuss(record.id, with: companion) }
          }
        }
      }
    }
  }

  private func cleanPreviewText(for record: SessionRecordHeader) -> String {
    record.preview.replacingOccurrences(of: "\n", with: " ")
  }
}
