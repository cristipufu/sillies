import SilliesChat
import SilliesCore
import SwiftUI

struct ChatMemoryEditorView: View {
  private enum Layout {
    static let spacing: CGFloat = 16
    static let padding: CGFloat = 20
    static let width: CGFloat = 360
    static let editorHeight: CGFloat = 100
    static let sourceHeight: CGFloat = 90
    static let editorPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 12
  }
  @Environment(\.silliesTheme) private var theme
  @Bindable var editor: ChatMemoryEditor

  var body: some View {
    VStack(alignment: .leading, spacing: Layout.spacing) {
      Label("Remember this…", systemImage: "sparkles").font(.title2.bold())
      HStack {
        TextField("Memory topic", text: $editor.topic).textFieldStyle(.roundedBorder)
        Text("\(editor.topic.count)/\(MemoryFact.maximumKeyCharacters)")
          .font(.caption.monospacedDigit()).foregroundStyle(theme.secondary)
      }
      TextEditor(text: $editor.value)
        .font(.body).scrollContentBackground(.hidden)
        .padding(Layout.editorPadding).frame(height: Layout.editorHeight)
        .background(theme.card, in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Layout.cornerRadius).strokeBorder(theme.border))
        .accessibilityLabel("Memory")
      HStack {
        Text("Review the fact before saving. You can undo it afterward.")
          .font(.caption).foregroundStyle(theme.secondary)
        Spacer()
        Text("\(editor.value.count)/\(MemoryFact.maximumValueCharacters)")
          .font(.caption.monospacedDigit()).foregroundStyle(theme.secondary)
      }
      DisclosureGroup("Source message") {
        ScrollView { Text(editor.sourceQuote).font(.callout).textSelection(.enabled) }
          .frame(maxHeight: Layout.sourceHeight)
      }
      if let failure = editor.failure {
        Text(failure).font(.caption).foregroundStyle(theme.secondary).textSelection(.enabled)
      }
      HStack {
        Button("Cancel") { editor.close() }.buttonStyle(SoftButtonStyle())
          .keyboardShortcut(.cancelAction).disabled(editor.isSaving)
        Spacer()
        if editor.isSaving { ProgressView().controlSize(.small) }
        Button("Save memory") { Task { await editor.save() } }
          .buttonStyle(AccentButtonStyle()).keyboardShortcut(.defaultAction)
          .disabled(!editor.canSave)
      }
    }.padding(Layout.padding).frame(width: Layout.width)
      .background(theme.paper).foregroundStyle(theme.ink).tint(theme.accent)
      .interactiveDismissDisabled(editor.isSaving)
  }
}
