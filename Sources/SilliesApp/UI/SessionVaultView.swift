import AppKit
import SilliesCore
import SwiftUI

struct SessionVaultView: View {
  let vault: SessionVaultStore
  @State private var selectedFilter: CompanionSkillKind?
  @State private var searchQuery = ""
  @State private var selectedRecordID: UUID?
  @State private var copiedFeedback: String?

  init(vault: SessionVaultStore, initialRecordID: UUID? = nil) {
    self.vault = vault
    _selectedRecordID = State(initialValue: initialRecordID ?? vault.records.first?.id)
  }

  private var filteredRecords: [SessionRecord] {
    vault.records.filter { record in
      if let selectedFilter, record.kind != selectedFilter { return false }
      let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard !query.isEmpty else { return true }
      return record.displayTitle.lowercased().contains(query)
        || record.summary.lowercased().contains(query)
        || record.transcript.lowercased().contains(query)
        || record.extractedText.lowercased().contains(query)
        || record.stashedItems.joined(separator: " ").lowercased().contains(query)
    }
  }

  private var selectedRecord: SessionRecord? {
    if let selectedRecordID,
      let match = filteredRecords.first(where: { $0.id == selectedRecordID })
    {
      return match
    }
    return filteredRecords.first
  }

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider().overlay(SilliesTheme.border)
      detailPane
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(SilliesTheme.paper)
    .foregroundStyle(SilliesTheme.ink)
  }

  private var sidebar: some View {
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
        Text("\(filteredRecords.count)")
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
        TextField("Search transcripts, OCR, stashes…", text: $searchQuery)
          .textFieldStyle(.plain)
          .font(.system(size: 12.5))
        if !searchQuery.isEmpty {
          Button {
            searchQuery = ""
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

      // Unified segmented filter bar
      HStack(spacing: 3) {
        filterChip(title: "All", kind: nil)
        ForEach(CompanionSkillKind.allCases) { kind in
          filterChip(title: kind.shortTitle, kind: kind)
        }
      }
      .padding(3)
      .background(SilliesTheme.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .frame(maxWidth: .infinity)

      if filteredRecords.isEmpty {
        emptySidebarState
      } else {
        ScrollView {
          LazyVStack(spacing: 9) {
            ForEach(filteredRecords) { record in
              recordRow(record, isSelected: selectedRecord?.id == record.id)
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
          .fill(SilliesTheme.soft)
          .frame(width: 52, height: 52)
        Image(systemName: "sparkles.rectangle.stack")
          .font(.system(size: 21, weight: .medium))
          .foregroundStyle(SilliesTheme.secondary)
      }
      Text(
        searchQuery.isEmpty && selectedFilter == nil
          ? "No sessions saved yet" : "No matching sessions"
      )
      .font(.system(size: 14, weight: .bold, design: .rounded))
      Text(
        "Drag a companion onto any window to Snap & OCR, Listen & Scribe, Watch, or Focus—or drop text and links onto a companion to Stash."
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

  private func filterChip(title: String, kind: CompanionSkillKind?) -> some View {
    let active = selectedFilter == kind
    return Button {
      selectedFilter = kind
    } label: {
      Text(title)
        .font(.system(size: 10.5, weight: active ? .bold : .semibold, design: .rounded))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5.5)
        .background(
          active ? SilliesTheme.accent : Color.clear,
          in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .foregroundStyle(active ? Color.white : SilliesTheme.secondary)
    }
    .buttonStyle(.plain)
  }

  private func recordRow(_ record: SessionRecord, isSelected: Bool) -> some View {
    Button {
      selectedRecordID = record.id
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
      return first
    }
    if !record.extractedText.isEmpty {
      return record.extractedText
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if !record.transcript.isEmpty {
      return record.transcript
    }
    return record.summary.replacingOccurrences(of: "• ", with: "")
  }

  @ViewBuilder
  private var detailPane: some View {
    if let record = selectedRecord {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          detailHeader(for: record)

          Divider().overlay(SilliesTheme.border.opacity(0.65))

          if needsPermissionBanner(for: record) {
            permissionBanner(for: record)
          }

          if let image = vault.loadImage(for: record) {
            snapshotStage(image: image, record: record)
          }

          if !record.stashedItems.isEmpty {
            stashedItemsCard(for: record)
          }

          let shouldShowSummary =
            !record.summary.isEmpty
            && !needsPermissionBanner(for: record)
            && !(record.kind == .stash && record.actionItems.isEmpty)
          if shouldShowSummary {
            let hasStructuredHighlights =
              record.summary.contains("•") || !record.transcript.isEmpty
              || !record.extractedText.isEmpty
            sectionCard(
              title: hasStructuredHighlights ? "SUMMARY & HIGHLIGHTS" : "SESSION NOTE",
              symbol: hasStructuredHighlights ? "sparkles" : "note.text"
            ) {
              Text(record.summary)
                .font(.system(size: 13))
                .lineSpacing(3.5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }

          if !record.actionItems.isEmpty {
            sectionCard(title: "ACTION ITEMS", symbol: "checklist") {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(record.actionItems, id: \.self) { item in
                  HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "checkmark.square.fill")
                      .font(.system(size: 12, weight: .semibold))
                      .foregroundStyle(SilliesTheme.accent)
                      .padding(.top, 1.5)
                    Text(item)
                      .font(.system(size: 12.5))
                      .lineSpacing(2)
                      .textSelection(.enabled)
                  }
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }

          if !record.transcript.isEmpty {
            sectionCard(
              title: "TRANSCRIPT", symbol: "waveform",
              trailingActionTitle: "Copy Transcript",
              trailingAction: {
                vault.copyText(record.transcript)
                flashCopied("Transcript copied")
              }
            ) {
              Text(record.transcript)
                .font(.system(size: 12.5))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }

          if !record.extractedText.isEmpty {
            sectionCard(
              title: "EXTRACTED WINDOW TEXT (OCR)", symbol: "text.viewfinder",
              trailingActionTitle: "Copy OCR Text",
              trailingAction: {
                vault.copyText(record.extractedText)
                flashCopied("OCR text copied")
              }
            ) {
              Text(record.extractedText)
                .font(.system(size: 12, design: .monospaced))
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                  SilliesTheme.paper,
                  in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
          }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(spacing: 12) {
        Image(systemName: "archivebox")
          .font(.system(size: 32, weight: .light))
          .foregroundStyle(SilliesTheme.secondary.opacity(0.5))
        Text("Select a session to inspect")
          .font(.system(size: 15, weight: .semibold, design: .rounded))
          .foregroundStyle(SilliesTheme.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func detailHeader(for record: SessionRecord) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      // Row 1: Category badge + attribution metadata on left, status + delete on right
      HStack(spacing: 8) {
        HStack(spacing: 5) {
          Image(systemName: record.kind.symbolName)
            .font(.system(size: 10.5, weight: .bold))
          Text(record.kind.title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4.5)
        .background(SilliesTheme.accent.opacity(0.14), in: Capsule())
        .foregroundStyle(SilliesTheme.accent)

        Text("by \(record.characterName)")
          .font(.system(size: 11.5, weight: .semibold, design: .rounded))
          .foregroundStyle(SilliesTheme.secondary)

        Text("· \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
          .font(.system(size: 11.5))
          .foregroundStyle(SilliesTheme.secondary)

        if record.durationSeconds >= 1 {
          Text("· \(SessionRecord.formatDuration(record.durationSeconds))")
            .font(.system(size: 11.5, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(SilliesTheme.secondary)
        }

        Spacer(minLength: 8)

        if let copiedFeedback {
          HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 11))
            Text(copiedFeedback)
              .font(.system(size: 11, weight: .bold, design: .rounded))
          }
          .foregroundStyle(Color(red: 0.28, green: 0.64, blue: 0.43))
          .padding(.horizontal, 10)
          .padding(.vertical, 4.5)
          .background(
            Color(red: 0.28, green: 0.64, blue: 0.43).opacity(0.12), in: Capsule())
        }

        Button {
          deleteRecord(record)
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "trash")
              .font(.system(size: 11, weight: .semibold))
            Text("Delete")
              .font(.system(size: 11, weight: .semibold, design: .rounded))
          }
          .foregroundStyle(SilliesTheme.secondary)
          .padding(.horizontal, 10)
          .frame(height: 28)
          .background(
            SilliesTheme.card,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(SilliesTheme.border, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .help("Delete session")
      }

      // Row 2: Unobstructed full-width title and window subtitle
      VStack(alignment: .leading, spacing: 4) {
        Text(record.appName)
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .tracking(-0.4)
          .foregroundStyle(SilliesTheme.ink)
        if let windowTitle = record.windowTitle, !windowTitle.isEmpty, windowTitle != record.appName
        {
          Text(windowTitle)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(SilliesTheme.secondary)
            .lineLimit(2)
        }
      }

      // Row 3: Dedicated horizontal action toolbar (never wraps or crowds metadata)
      HStack(spacing: 9) {
        if record.imageFilename != nil {
          toolbarButton(
            "Copy Image", symbol: "photo.on.rectangle.angled", prominent: true
          ) {
            vault.copyImage(for: record)
            flashCopied("Image copied")
          }
        }
        if !record.primaryText.isEmpty {
          toolbarButton(
            record.kind == .snap ? "Copy OCR Text" : "Copy Text",
            symbol: "doc.on.doc",
            prominent: record.imageFilename == nil
          ) {
            vault.copyText(record.primaryText)
            flashCopied("Text copied")
          }
        }
        toolbarButton(
          "Copy Markdown", symbol: "square.and.arrow.up", prominent: false
        ) {
          vault.copyText(record.markdownExport)
          flashCopied("Markdown copied")
        }
        Spacer()
      }
      .padding(.top, 2)
    }
  }

  private func stashedItemsCard(for record: SessionRecord) -> some View {
    sectionCard(
      title: "STASHED ITEMS (\(record.stashedItems.count))",
      symbol: "tray.full.fill",
      trailingActionTitle: record.stashedItems.count > 1 ? "Copy All" : nil,
      trailingAction: record.stashedItems.count > 1
        ? {
          vault.copyText(record.stashedItems.joined(separator: "\n"))
          flashCopied("All items copied")
        } : nil
    ) {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(record.stashedItems.enumerated()), id: \.offset) { _, item in
          let isLink =
            item.lowercased().hasPrefix("http://") || item.lowercased().hasPrefix("https://")
          let isFile = item.hasPrefix("/")
          HStack(alignment: .center, spacing: 11) {
            ZStack {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SilliesTheme.accent.opacity(0.11))
                .frame(width: 28, height: 28)
              Image(systemName: isLink ? "link" : (isFile ? "doc.fill" : "text.quote"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(SilliesTheme.accent)
            }

            Text(item)
              .font(
                .system(
                  size: 12.5, weight: .medium,
                  design: isLink || isFile ? .monospaced : .default)
              )
              .lineSpacing(2.5)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
              if isLink, let url = URL(string: item) {
                Button {
                  NSWorkspace.shared.open(url)
                } label: {
                  HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                      .font(.system(size: 10, weight: .bold))
                    Text("Open")
                      .font(.system(size: 11, weight: .semibold, design: .rounded))
                  }
                  .foregroundStyle(SilliesTheme.accent)
                  .padding(.horizontal, 9)
                  .frame(height: 26)
                  .background(
                    SilliesTheme.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
              }

              Button {
                vault.copyText(item)
                flashCopied("Item copied")
              } label: {
                HStack(spacing: 4) {
                  Image(systemName: "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                  Text("Copy")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(SilliesTheme.ink)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(
                  SilliesTheme.card,
                  in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(SilliesTheme.border, lineWidth: 0.75))
              }
              .buttonStyle(.plain)
            }
          }
          .padding(11)
          .background(
            SilliesTheme.paper,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(SilliesTheme.border.opacity(0.55), lineWidth: 0.7))
        }
      }
    }
  }

  private func snapshotStage(image: NSImage, record: SessionRecord) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: "camera.viewfinder")
          .font(.system(size: 10.5, weight: .bold))
          .foregroundStyle(SilliesTheme.accent)
        Text("CAPTURED WINDOW SNAPSHOT")
          .font(.system(size: 10, weight: .bold))
          .tracking(1.1)
          .foregroundStyle(SilliesTheme.secondary)
        Spacer()
        Text("\(Int(image.size.width)) × \(Int(image.size.height)) px")
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .foregroundStyle(SilliesTheme.secondary)
      }

      ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(SilliesTheme.soft.opacity(0.65))
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
          .frame(maxHeight: 300)
          .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          .shadow(color: .black.opacity(0.14), radius: 9, y: 3)
          .padding(14)
      }
      .frame(maxWidth: .infinity)
    }
    .padding(16)
    .background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 15, style: .continuous)
        .strokeBorder(SilliesTheme.border.opacity(0.8), lineWidth: 0.75))
  }

  private func needsPermissionBanner(for record: SessionRecord) -> Bool {
    record.summary.localizedCaseInsensitiveContains("Screen Recording permission")
      || record.summary.localizedCaseInsensitiveContains("System Settings")
  }

  private func permissionBanner(for record: SessionRecord) -> some View {
    HStack(spacing: 14) {
      Image(systemName: "lock.shield.fill")
        .font(.system(size: 21))
        .foregroundStyle(Color.orange)
      VStack(alignment: .leading, spacing: 4) {
        Text("Screen & Audio Recording Access Needed")
          .font(.system(size: 13, weight: .bold, design: .rounded))
        Text(record.summary)
          .font(.system(size: 11.5))
          .lineSpacing(2)
          .foregroundStyle(SilliesTheme.secondary)
      }
      Spacer(minLength: 10)
      HStack(spacing: 8) {
        Button("Refresh Permission") {
          WindowSnapshotService.resetAndRequestPermission()
        }
        .buttonStyle(SoftButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
        .help(
          "Resets stale macOS permission cache from older local builds and opens Screen & System Audio Recording"
        )
        Button("Open System Settings") {
          WindowSnapshotService.openSystemSettings()
        }
        .buttonStyle(SoftButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
      }
    }
    .padding(16)
    .background(
      Color.orange.opacity(0.08),
      in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.9))
  }

  private func deleteRecord(_ record: SessionRecord) {
    let currentList = filteredRecords
    if selectedRecord?.id == record.id {
      if let index = currentList.firstIndex(where: { $0.id == record.id }) {
        if index + 1 < currentList.count {
          selectedRecordID = currentList[index + 1].id
        } else if index > 0 {
          selectedRecordID = currentList[index - 1].id
        } else {
          selectedRecordID = nil
        }
      }
    }
    vault.remove(id: record.id)
  }

  private func toolbarButton(
    _ title: String, symbol: String, prominent: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: symbol)
          .font(.system(size: 11, weight: .semibold))
        Text(title)
          .font(.system(size: 11.5, weight: .semibold, design: .rounded))
          .lineLimit(1)
      }
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, 13)
      .frame(height: 31)
      .foregroundStyle(prominent ? Color.white : SilliesTheme.ink)
      .background(
        prominent ? SilliesTheme.accent : SilliesTheme.card,
        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .strokeBorder(prominent ? Color.clear : SilliesTheme.border, lineWidth: 0.8))
    }
    .buttonStyle(.plain)
  }

  private func sectionCard<Content: View>(
    title: String, symbol: String,
    trailingActionTitle: String? = nil,
    trailingAction: (() -> Void)? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 7) {
        Image(systemName: symbol)
          .font(.system(size: 10.5, weight: .bold))
          .foregroundStyle(SilliesTheme.accent)
        Text(title)
          .font(.system(size: 10, weight: .bold))
          .tracking(1.1)
          .foregroundStyle(SilliesTheme.secondary)
        Spacer()
        if let trailingActionTitle, let trailingAction {
          Button(action: trailingAction) {
            HStack(spacing: 5) {
              Image(systemName: "doc.on.doc")
                .font(.system(size: 9.5, weight: .semibold))
              Text(trailingActionTitle)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(SilliesTheme.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
              SilliesTheme.accent.opacity(0.10),
              in: RoundedRectangle(cornerRadius: 7, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(
        SilliesTheme.border.opacity(0.80), lineWidth: 0.75))
  }

  private func flashCopied(_ message: String) {
    copiedFeedback = message
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
      if copiedFeedback == message { copiedFeedback = nil }
    }
  }
}
