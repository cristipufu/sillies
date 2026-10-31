import SilliesCore
import SwiftUI

struct WritingHistoryView: View {
  let model: WritingHistory
  let copy: (String) -> Void
  @State private var confirmsDeletion = false
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Writing recovery").font(.title2.bold())
        Spacer()
        Button("Delete all…", role: .destructive) { confirmsDeletion = true }
          .disabled(model.results.isEmpty)
      }
      Text(
        "The latest 20 dictations and selection edits stay on this Mac, separately from meetings. Audio is not saved."
      )
      .font(.callout).foregroundStyle(.secondary)
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
        List(model.results) { result in
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text(result.applicationName).fontWeight(.semibold)
              Spacer()
              Text(result.createdAt, style: .time).foregroundStyle(.secondary)
            }
            Text(result.text).textSelection(.enabled)
            if !result.notice.isEmpty {
              Text(result.notice).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
              Button("Copy") { copy(result.text) }
              if result.text != result.originalText {
                Button("Copy original") { copy(result.originalText) }
              }
              Spacer()
              Button("Delete", role: .destructive) { model.remove(result.id) }
            }
          }.padding(.vertical, 8)
        }
      }
    }.padding(22).frame(minWidth: 520, minHeight: 380)
      .confirmationDialog("Delete all recent writing?", isPresented: $confirmsDeletion) {
        Button("Delete all", role: .destructive) { model.clear() }
      }
  }
}
