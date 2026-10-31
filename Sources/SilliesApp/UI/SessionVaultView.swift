import AppKit
import SilliesCore
import SwiftUI

struct SessionVaultView: View {
  private static let maxSidebarPreviewCharacters = 240
  let vault: SessionVaultStore
  @State private var model: SessionVaultModel
  @State private var showsStashComposer = false
  @State private var showsRetention = false

  init(
    vault: SessionVaultStore, initialRecordID: UUID? = nil, pasteBack: PasteBackCoordinator? = nil
  ) {
    self.vault = vault
    _model = State(
      initialValue: SessionVaultModel(
        vault: vault, initialRecordID: initialRecordID, pasteBack: pasteBack))
  }

  var body: some View {
    let records = model.filteredRecords
    let current = model.selectedRecord(in: records)
    HStack(spacing: 0) {
      sidebar(records: records, selected: current)
      Divider().overlay(SilliesTheme.border)
      SessionVaultDetailView(vault: vault, model: model, record: current)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(SilliesTheme.paper)
    .foregroundStyle(SilliesTheme.ink)
    .onDisappear { model.stop() }
    .task(id: model.searchIdentity) { await model.refreshSearch() }
    .sheet(isPresented: $showsStashComposer) {
      StashComposerView { model.saveStash([$0]) }
    }
    .sheet(isPresented: $showsRetention) { VaultRetentionView(vault: vault) }
  }

  private func sidebar(records: [SessionRecord], selected: SessionRecord?) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(SilliesTheme.accent.opacity(0.14))
            .frame(width: 34, height: 34)
          Image(systemName: "archivebox.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(SilliesTheme.accent)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text("Session Vault")
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .tracking(-0.3)
          Text("Captures, transcripts & stashes")
            .font(.system(size: 11))
            .foregroundStyle(SilliesTheme.secondary)
        }
        Spacer(minLength: 4)
        Text("\(records.count)")
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .monospacedDigit()
          .padding(.horizontal, 9)
          .padding(.vertical, 3.5)
          .background(SilliesTheme.soft, in: Capsule())
          .foregroundStyle(SilliesTheme.secondary)
      }

      // Search field
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(SilliesTheme.secondary)
        TextField(
          "Search transcripts, OCR, stashes…",
          text: Binding(get: { model.searchQuery }, set: { model.searchQuery = $0 })
        )
        .textFieldStyle(.plain)
        .font(.system(size: 12.5))
        if !model.searchQuery.isEmpty {
          Button {
            model.searchQuery = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 12))
              .foregroundStyle(SilliesTheme.secondary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 11)
      .frame(height: 34)
      .background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(SilliesTheme.border, lineWidth: 0.8))

      HStack {
        Button("Add text / link", systemImage: "plus") { showsStashComposer = true }
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
        Button("Retention…") { showsRetention = true }
        Spacer()
        Button("Export all…") { model.exportAll() }.disabled(vault.records.isEmpty)
      }.font(.caption)

      if let error = vault.persistenceError {
        Text(error).font(.caption).foregroundStyle(.orange)
        Button("Retry saving") { vault.retrySaving() }
      }

      if model.isSearching { ProgressView("Searching…").font(.caption) }
      if let error = model.searchError { Text(error).font(.caption).foregroundStyle(.red) }
      if records.isEmpty {
        emptySidebarState
      } else {
        ScrollView {
          LazyVStack(spacing: 9) {
            ForEach(records) { record in
              recordRow(record, isSelected: selected?.id == record.id)
            }
            if model.hasMoreResults { Button("Show more") { model.showMore() } }
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
          .fill(SilliesTheme.soft)
          .frame(width: 52, height: 52)
        Image(systemName: "sparkles.rectangle.stack")
          .font(.system(size: 21, weight: .medium))
          .foregroundStyle(SilliesTheme.secondary)
      }
      Text(
        model.searchQuery.isEmpty && model.selectedFilter == nil
          ? "No sessions saved yet" : "No matching sessions"
      )
      .font(.system(size: 14, weight: .bold, design: .rounded))
      Text(
        "Drag a companion onto a window to choose a skill. Record from the menu bar, or add text and links here to Pocket Stash."
      )
      .font(.system(size: 11.5))
      .foregroundStyle(SilliesTheme.secondary)
      .multilineTextAlignment(.center)
      .lineSpacing(2.5)
      .padding(.horizontal, 16)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private func recordRow(_ record: SessionRecord, isSelected: Bool) -> some View {
    Button {
      model.selectedRecordID = record.id
    } label: {
      HStack(alignment: .top, spacing: 11) {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? SilliesTheme.accent : SilliesTheme.accent.opacity(0.12))
            .frame(width: 32, height: 32)
          Image(systemName: record.kind.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isSelected ? Color.white : SilliesTheme.accent)
        }

        VStack(alignment: .leading, spacing: 5) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(record.appName)
              .font(.system(size: 13, weight: .bold, design: .rounded))
              .foregroundStyle(SilliesTheme.ink)
              .lineLimit(1)
            Spacer(minLength: 4)
            Text(record.createdAt.formatted(date: .omitted, time: .shortened))
              .font(.system(size: 10, weight: .medium))
              .monospacedDigit()
              .foregroundStyle(SilliesTheme.secondary)
          }

          if let title = record.windowTitle, !title.isEmpty, title != record.appName {
            Text(title)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(SilliesTheme.secondary)
              .lineLimit(1)
          }

          Text(cleanPreviewText(for: record))
            .font(.system(size: 11))
            .foregroundStyle(SilliesTheme.ink.opacity(0.80))
            .lineSpacing(1.5)
            .lineLimit(2)
            .multilineTextAlignment(.leading)

          HStack(spacing: 6) {
            Text(record.kind.shortTitle)
              .font(.system(size: 9.5, weight: .bold, design: .rounded))
              .foregroundStyle(SilliesTheme.accent)
            Text("· \(record.characterName)")
              .font(.system(size: 9.5, weight: .medium, design: .rounded))
              .foregroundStyle(SilliesTheme.secondary)
            if record.durationSeconds >= 1 {
              Text("· \(SessionRecord.formatDuration(record.durationSeconds))")
                .font(.system(size: 9.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(SilliesTheme.secondary)
            }
            if record.kind == .stash && !record.stashedItems.isEmpty {
              Text(
                "· \(record.stashedItems.count) item\(record.stashedItems.count == 1 ? "" : "s")"
              )
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(SilliesTheme.secondary)
            }
            if record.imageFilename != nil {
              Spacer()
              Image(systemName: "photo")
                .font(.system(size: 9.5))
                .foregroundStyle(SilliesTheme.secondary)
            }
          }
          .padding(.top, 1)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        isSelected ? SilliesTheme.accent.opacity(0.10) : SilliesTheme.card,
        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(
          isSelected ? SilliesTheme.accent : SilliesTheme.border.opacity(0.80),
          lineWidth: isSelected ? 1.4 : 0.75))
    }
    .buttonStyle(.plain)
  }

  private func cleanPreviewText(for record: SessionRecord) -> String {
    if record.kind == .stash, let first = record.stashedItems.first {
      return String(first.prefix(Self.maxSidebarPreviewCharacters))
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if !record.extractedText.isEmpty {
      return String(record.extractedText.prefix(Self.maxSidebarPreviewCharacters))
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if !record.transcript.isEmpty {
      return String(record.transcript.prefix(Self.maxSidebarPreviewCharacters))
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return String(record.summary.prefix(Self.maxSidebarPreviewCharacters))
      .replacingOccurrences(of: "• ", with: "")
  }

}
