import AppKit
import SilliesCore
import SwiftUI

struct SessionVaultDetailView: View {
  private static let maxDetailDisplayCharacters = 8_192
  let vault: SessionVaultStore
  let model: SessionVaultModel
  let record: SessionRecord?
  private struct SectionAction {
    let title: String
    let perform: () -> Void
  }
  private struct PreviewIdentity: Hashable {
    let recordID: UUID
    let hasImage: Bool
  }

  var body: some View {
    if let record {
      let previewImage = vault.cachedImage(for: record)
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          SessionVaultDetailHeader(record: record, model: model)

          Divider().overlay(SilliesTheme.border.opacity(0.65))

          if let failure = record.failure {
            SessionFailureNotice(
              failure: failure,
              refreshScreenRecordingPermission: WindowSnapshotService.resetAndRequestPermission)
          }

          if let image = previewImage {
            snapshotStage(image: image)
          }

          if let audioURL = vault.audioURL(for: record) {
            RecordingPlaybackView(url: audioURL).id(record.id)
          }
          if record.summaryPending {
            HStack {
              ProgressView().controlSize(.small)
              Text("Preparing local notes…").font(.callout)
            }
          }
          if !record.summaryPending, !record.transcript.isEmpty || !record.extractedText.isEmpty {
            Button {
              model.regenerateNotes(record)
            } label: {
              Label("Regenerate notes", systemImage: "arrow.clockwise")
            }.buttonStyle(SoftButtonStyle())
              .help(
                "Use the model selected in Settings → Local AI. Your transcript stays unchanged.")
          }
          if record.screenshotTextState == .pending {
            ProgressView("Recognizing screenshot text in the background…").font(.callout)
          } else if record.screenshotTextState == .failed {
            Button("Retry screenshot text recognition") { model.retryScreenshotText(record.id) }
          }

          if !record.processingNote.isEmpty {
            Text(record.processingNote).font(.callout).foregroundStyle(SilliesTheme.secondary)
              .textSelection(.enabled)
          }
          if !record.notesNotice.isEmpty {
            Text(record.notesNotice).font(.callout).foregroundStyle(SilliesTheme.secondary)
              .textSelection(.enabled)
          }
          if !record.explanation.isEmpty {
            sectionCard(title: "EXPLANATION", symbol: "text.bubble") {
              Text(Self.boundedDisplayText(record.explanation)).lineSpacing(4).textSelection(
                .enabled)
            }
          }
          if !record.suggestions.isEmpty {
            sectionCard(title: "MEETING SUGGESTIONS", symbol: "pawprint.fill") {
              VStack(spacing: 10) {
                ForEach(record.suggestions) { MeetingSuggestionView(suggestion: $0) }
              }
            }
          }
          if !record.stashedItems.isEmpty {
            stashedItemsCard(for: record)
            Text(
              "File entries are references to the original files. Pocket Stash keeps saved items until you delete them."
            )
            .font(.caption).foregroundStyle(SilliesTheme.secondary)
          }

          let shouldShowSummary =
            !record.summary.isEmpty
            && !(record.kind == .stash && record.actionItems.isEmpty)
          if shouldShowSummary {
            let hasStructuredHighlights =
              record.summary.contains("•") || !record.transcript.isEmpty
              || !record.extractedText.isEmpty
            sectionCard(
              title: hasStructuredHighlights
                ? record.notesSource.title.uppercased() : "SESSION NOTE",
              symbol: hasStructuredHighlights ? "sparkles" : "note.text"
            ) {
              if record.notesSource == .extracted {
                Text(
                  "Selected excerpts from the transcript, not an AI summary. Open the full transcript for context."
                )
                .font(.caption).foregroundStyle(SilliesTheme.secondary).textSelection(.enabled)
              }
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
            SpeakerNamingView(record: record) { model.rename($0, to: $1, in: record) }.id(record.id)
            sectionCard(
              title: "TRANSCRIPT", symbol: "waveform",
              action: SectionAction(
                title: "Copy Transcript",
                perform: {
                  model.copyText(record.transcript, feedback: "Transcript copied")
                })
            ) {
              Text(Self.boundedDisplayText(record.transcript))
                .font(.system(size: 12.5)).lineSpacing(4).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
              Button("Open full transcript") { model.openTranscript(record) }
            }
          }

          if !record.extractedText.isEmpty {
            sectionCard(
              title: "EXTRACTED WINDOW TEXT (OCR)", symbol: "text.viewfinder",
              action: SectionAction(
                title: "Copy OCR Text",
                perform: {
                  model.copyText(record.extractedText, feedback: "OCR text copied")
                })
            ) {
              Text(Self.boundedDisplayText(record.extractedText))
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
      .task(id: PreviewIdentity(recordID: record.id, hasImage: previewImage != nil)) {
        vault.pin(record)
      }
    } else {
      VStack(spacing: 12) {
        Image(systemName: "archivebox")
          .font(.system(size: 32, weight: .light))
          .foregroundStyle(SilliesTheme.secondary.opacity(0.5))
        if let error = model.detailError {
          Text(error).textSelection(.enabled).multilineTextAlignment(.center)
          Button("Try again") { Task { await model.loadSelection() } }.buttonStyle(
            SoftButtonStyle())
        } else if model.isLoadingDetail || vault.isLoading {
          ProgressView("Opening session…").controlSize(.small)
        } else {
          Text("Select a session to inspect")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(SilliesTheme.secondary)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func stashedItemsCard(for record: SessionRecord) -> some View {
    sectionCard(
      title: "STASHED ITEMS (\(record.stashedItems.count))",
      symbol: "tray.full.fill",
      action: record.stashedItems.count > 1
        ? SectionAction(
          title: "Copy All",
          perform: {
            model.copyText(
              record.stashedItems.joined(separator: "\n"), feedback: "All items copied")
          }) : nil
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

            Text(Self.boundedDisplayText(item))
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
                model.copyText(item, feedback: "Item copied")
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

  private func snapshotStage(image: NSImage) -> some View {
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

  private static func boundedDisplayText(_ text: String) -> String {
    guard text.count > maxDetailDisplayCharacters else { return text }
    return
      "\(text.prefix(maxDetailDisplayCharacters))\n\n… [Showing first \(maxDetailDisplayCharacters) of \(text.count) characters — use Copy to copy full text]"
  }

  private func sectionCard<Content: View>(
    title: String, symbol: String,
    action: SectionAction? = nil,
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
        if let action {
          Button(action: action.perform) {
            HStack(spacing: 5) {
              Image(systemName: "doc.on.doc")
                .font(.system(size: 9.5, weight: .semibold))
              Text(action.title)
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

}
