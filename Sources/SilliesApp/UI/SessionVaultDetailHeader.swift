import SilliesCore
import SwiftUI

struct SessionVaultDetailHeader: View {
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

        if let copiedFeedback = model.feedback {
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
          model.delete(record)
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
            "Copy Image", symbol: "photo.on.rectangle.angled", emphasis: .prominent
          ) {
            model.copyImage(for: record)
          }
        }
        if !record.primaryText.isEmpty {
          toolbarButton(
            record.kind == .snap ? "Copy OCR Text" : "Copy Text",
            symbol: "doc.on.doc",
            emphasis: record.imageFilename == nil ? .prominent : .standard
          ) {
            model.copyText(record.primaryText, feedback: "Text copied")
          }
        }
        toolbarButton(
          "Copy Markdown", symbol: "square.and.arrow.up", emphasis: .standard
        ) {
          model.copyText(SessionMarkdownFormatter.format(record), feedback: "Markdown copied")
        }
        Menu {
          if let pasteBack = model.pasteBack, pasteBack.destination != nil {
            Button(pasteBack.actionTitle) { model.paste(record) }.disabled(pasteBack.isPasting)
          }
          Button("Export Markdown & attachments…") { model.export([record]) }
          Button(record.isProtected ? "Remove protection" : "Protect from automatic deletion") {
            model.toggleProtection(record)
          }
        } label: {
          Image(systemName: record.isProtected ? "pin.fill" : "ellipsis.circle")
        }
        .help(record.isProtected ? "Protected from automatic deletion" : "More actions")
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
      .foregroundStyle(emphasis == .prominent ? Color.white : SilliesTheme.ink)
      .background(
        emphasis == .prominent ? SilliesTheme.accent : SilliesTheme.card,
        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .strokeBorder(emphasis == .prominent ? Color.clear : SilliesTheme.border, lineWidth: 0.8))
    }
    .buttonStyle(.plain)
  }

}
