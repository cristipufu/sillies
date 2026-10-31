import SilliesCore
import SwiftUI

struct WritingHistoryView: View {
  private static let previewCharacters = 400
  let model: WritingHistory
  let copy: (String) -> Void
  let openText: (WritingResult) -> Void
  @State private var confirmsDeletion = false
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      SessionIdentityHeader(title: "Recent writing", symbol: "text.bubble") {
        Text("Dictations & selection edits · On this Mac")
      } accessory: {
        Button("Delete all…", role: .destructive) { confirmsDeletion = true }
          .buttonStyle(SoftButtonStyle()).disabled(model.results.isEmpty)
      }
      Text(
        "Your latest 20 results stay here, separately from meetings. Audio isn’t saved."
      ).font(.callout).foregroundStyle(SilliesTheme.secondary)
      if let error = model.error {
        Text(error).foregroundStyle(.red)
        Button("Retry loading history") { Task { await model.load() } }
      }
      if model.results.isEmpty {
        ContentUnavailableView(
          "No recent writing", systemImage: "waveform",
          description: Text(
            "Your next result will appear here, including text that could not be inserted."))
      } else {
        ScrollView {
          LazyVStack(spacing: 12) {
            ForEach(model.results) { result in
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                  Text(result.applicationName).fontWeight(.semibold)
                  Spacer()
                  Text(result.createdAt, style: .time).foregroundStyle(SilliesTheme.secondary)
                }
                Text(String(result.text.prefix(Self.previewCharacters))).lineLimit(4)
                if !result.notice.isEmpty {
                  Text(result.notice).font(.caption).foregroundStyle(SilliesTheme.secondary)
                }
                HStack {
                  Button("Open text") { openText(result) }
                  Button("Copy", systemImage: "doc.on.doc") { copy(result.text) }.buttonStyle(
                    SoftButtonStyle())
                  if result.text != result.originalText {
                    Button("Copy original") { copy(result.originalText) }
                  }
                  Spacer()
                  Button("Delete", role: .destructive) { model.remove(result.id) }
                }
              }.padding(16)
                .background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(SilliesTheme.border))
            }
          }.padding(1)
        }
      }
    }.padding(24).frame(minWidth: 560, minHeight: 400)
      .background(SilliesTheme.paper).foregroundStyle(SilliesTheme.ink).tint(SilliesTheme.accent)
      .confirmationDialog("Delete all recent writing?", isPresented: $confirmsDeletion) {
        Button("Delete all", role: .destructive) { model.clear() }
      }
  }
}
