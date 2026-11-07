import SilliesCore
import SwiftUI

struct VaultWorkspaceComposer: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var model: VaultWorkspaceModel
  @FocusState private var linkFocused: Bool
  private enum Layout {
    static let maximumWidth: CGFloat = 680
    static let horizontalPadding: CGFloat = 32
    static let fieldSpacing: CGFloat = 20
    static let notesHeight: CGFloat = 180
    static let footerPadding: CGFloat = 20
  }
  private var isLink: Bool { model.composer == .link }
  private var isDocument: Bool { model.composer == .note || isLink }
  private var heading: String {
    switch model.composer {
    case .link: String(localized: "Something worth saving")
    case .note: String(localized: "A fresh page")
    case .collection: String(localized: "New collection")
    case .savedSearch: String(localized: "Save this search")
    case .renameCollection: String(localized: "Rename collection")
    case .renameSearch: String(localized: "Rename saved search")
    case nil: ""
    }
  }
  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        fields.disabled(model.isSaving).padding(.horizontal, Layout.horizontalPadding).padding(
          .vertical, Layout.fieldSpacing)
      }
      Divider().overlay(theme.border)
      actions.padding(.horizontal, Layout.horizontalPadding).padding(
        .vertical, Layout.footerPadding)
    }.frame(maxWidth: Layout.maximumWidth, maxHeight: .infinity, alignment: .topLeading)
      .frame(maxWidth: .infinity).task(id: model.composer) { linkFocused = isLink }
  }

  private var fields: some View {
    VStack(alignment: .leading, spacing: Layout.fieldSpacing) {
      Button("Back to library", systemImage: "chevron.left") { model.showLibrary() }.buttonStyle(
        .plain
      ).foregroundStyle(theme.secondary)
      Text(heading).font(.system(size: 26, weight: .bold, design: .rounded))
      if isLink {
        Text("Articles, X posts, YouTube videos — keep the link and your thoughts together.")
          .font(.callout).foregroundStyle(theme.secondary)
        TextField("Paste a link", text: $model.composeLink).textFieldStyle(.roundedBorder).focused(
          $linkFocused
        )
        .onSubmit { Task { await model.saveComposedItem() } }
      }
      TextField(
        isLink ? String(localized: "Title (optional)") : String(localized: "Title"),
        text: $model.composeTitle
      )
      .textFieldStyle(.roundedBorder).font(.system(size: 16, weight: .medium))
      if isDocument {
        Text("Your notes").font(.headline)
        TextEditor(text: $model.composeNotes).font(.system(size: 14)).scrollContentBackground(
          .hidden
        )
        .padding(12).frame(height: Layout.notesHeight)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border, lineWidth: 1) }
        if isLink {
          Text(
            "The link is saved immediately. A preview is fetched in the background from the website; unavailable previews never prevent saving."
          )
          .font(.caption).foregroundStyle(theme.secondary)
        }
      }
      if let error = model.error {
        Text(error).font(.callout).foregroundStyle(theme.danger).textSelection(.enabled)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private var actions: some View {
    HStack {
      Button("Cancel") { model.showLibrary() }.buttonStyle(SoftButtonStyle())
        .disabled(model.isSaving)
        .keyboardShortcut(.cancelAction)
      Spacer()
      if model.isSaving { ProgressView().controlSize(.small) }
      Button("Save") { Task { await model.saveComposedItem() } }.buttonStyle(AccentButtonStyle())
        .disabled(!model.canSaveComposition)
        .keyboardShortcut(.return, modifiers: .command)
    }
  }
}
