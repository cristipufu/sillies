import SilliesCore
import SwiftUI

struct SessionVaultDetailHeader: View {
  @Environment(\.silliesTheme) private var theme
  private enum ButtonEmphasis { case standard, prominent }
  let record: SessionRecord
  let model: SessionVaultModel

  var body: some View {
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
        .background(theme.accent.opacity(0.14), in: Capsule())
        .foregroundStyle(theme.accent)

        Text("by \(record.characterName)")
          .font(.system(size: 11.5, weight: .semibold, design: .rounded))
          .foregroundStyle(theme.secondary)

        Text("· \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
          .font(.system(size: 11.5))
          .foregroundStyle(theme.secondary)

        if record.durationSeconds >= 1 {
          Text("· \(SessionRecord.formatDuration(record.durationSeconds))")
            .font(.system(size: 11.5, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(theme.secondary)
        }

        Spacer(minLength: 8)

        if let copiedFeedback = model.feedback {
          HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 11))
            Text(copiedFeedback)
              .font(.system(size: 11, weight: .bold, design: .rounded))
          }
          .foregroundStyle(theme.success)
          .padding(.horizontal, 10)
          .padding(.vertical, 4.5)
          .background(
            theme.success.opacity(0.12), in: Capsule())
        }

        Button {
          model.delete(record)
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "trash")
              .font(.system(size: 11, weight: .semibold))
            Text("Delete")
              .font(.system(size: 11, weight: .semibold, design: .rounded))
          }
          .foregroundStyle(theme.secondary)
          .padding(.horizontal, 10)
          .frame(height: 28)
          .background(
            theme.card,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(theme.border, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .help("Delete session")
      }

      // Row 2: Unobstructed full-width title and window subtitle
      VStack(alignment: .leading, spacing: 4) {
        Text(record.appName)
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .tracking(-0.4)
          .foregroundStyle(theme.ink)
        if let windowTitle = record.windowTitle, !windowTitle.isEmpty, windowTitle != record.appName
        {
          Text(windowTitle)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(theme.secondary)
            .lineLimit(2)
        }
      }

      // Row 3: Dedicated horizontal action toolbar (never wraps or crowds metadata)
      HStack(spacing: 9) {
        if let discussion = model.discussion, !discussion.companions.isEmpty {
          Menu("Discuss with…") {
            ForEach(discussion.companions, id: \.id) { companion in
              Button(companion.name) { model.discuss(record.id, with: companion) }
            }
          }.help("Choose a companion to discuss this item")
        }
        if record.imageFilename != nil {
          toolbarButton(
            String(localized: "Copy Image"), symbol: "photo.on.rectangle.angled",
            emphasis: .prominent
          ) {
            model.copyImage(for: record)
          }
        }
        if !record.primaryText.isEmpty {
          toolbarButton(
            record.kind == .snap
              ? String(localized: "Copy OCR Text") : String(localized: "Copy Text"),
            symbol: "doc.on.doc",
            emphasis: record.imageFilename == nil ? .prominent : .standard
          ) {
            model.copyText(record.primaryText, feedback: String(localized: "Text copied"))
          }
        }
        Menu {
          Button("Copy Markdown") {
            model.copyText(
              SessionMarkdownFormatter.format(record),
              feedback: String(localized: "Markdown copied"))
          }
          if let pasteBack = model.pasteBack, pasteBack.destination != nil {
            Button(pasteBack.actionTitle) { model.paste(record) }.disabled(pasteBack.isPasting)
          }
          Button("Export Markdown & attachments…") { model.export([record]) }
          Button(
            record.isProtected
              ? String(localized: "Remove protection")
              : String(localized: "Protect from automatic deletion")
          ) {
            model.toggleProtection(record)
          }
        } label: {
          Image(systemName: record.isProtected ? "pin.fill" : "ellipsis.circle")
        }
        .help(
          record.isProtected
            ? String(localized: "Protected from automatic deletion")
            : String(localized: "More actions"))
      }
      .padding(.top, 2)
    }
  }

  private func toolbarButton(
    _ title: String, symbol: String, emphasis: ButtonEmphasis, action: @escaping () -> Void
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
      .foregroundStyle(emphasis == .prominent ? theme.onAccent : theme.ink)
      .background(
        emphasis == .prominent ? theme.accentFill : theme.card,
        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .strokeBorder(emphasis == .prominent ? Color.clear : theme.border, lineWidth: 0.8))
    }
    .buttonStyle(.plain)
  }

}
