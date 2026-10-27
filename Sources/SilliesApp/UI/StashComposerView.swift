import SwiftUI

struct StashComposerView: View {
  let save: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Add to Pocket Stash", systemImage: "tray.and.arrow.down")
        .font(.title2.weight(.semibold))
      Text("Paste a link, write a note, or keep a snippet for later.")
        .foregroundStyle(.secondary)
      TextEditor(text: $text).font(.body).focused($focused)
        .frame(width: 420, height: 180).scrollContentBackground(.hidden)
        .padding(10).background(SilliesTheme.soft, in: RoundedRectangle(cornerRadius: 10))
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Save") {
          save(text)
          dismiss()
        }
        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(24).background(SilliesTheme.paper).tint(SilliesTheme.accent)
      .onAppear { focused = true }
  }
}
