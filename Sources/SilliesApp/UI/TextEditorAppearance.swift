import AppKit

/// Native editors share the palette without replacing their text or selection.
@MainActor enum TextEditorAppearance {
  static func apply(to editor: NSTextView) {
    editor.textColor = SilliesTheme.native(.ink)
    editor.insertionPointColor = SilliesTheme.native(.ink)
    editor.selectedTextAttributes = [
      .backgroundColor: SilliesTheme.native(.selection),
      .foregroundColor: SilliesTheme.native(.onSelection),
    ]
  }
}
