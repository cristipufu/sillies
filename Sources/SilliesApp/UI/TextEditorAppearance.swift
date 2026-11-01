import AppKit

/// Native editors share the palette without replacing their text or selection.
@MainActor enum TextEditorAppearance {
  static func apply(_ theme: SilliesTheme, to editor: NSTextView) {
    editor.textColor = theme.native(.ink)
    editor.insertionPointColor = theme.native(.ink)
    editor.selectedTextAttributes = [
      .backgroundColor: theme.native(.selection),
      .foregroundColor: theme.native(.onSelection),
    ]
  }
}
