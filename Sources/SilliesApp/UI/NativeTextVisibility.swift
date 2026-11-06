import AppKit
import SwiftUI

extension EnvironmentValues {
  @Entry var chatTextPresentation = NativeTextVisibility.Presentation.visible
}

/// Concealed native editors must release keyboard focus without losing their text selection.
enum NativeTextVisibility {
  enum Presentation: Sendable { case visible, concealed }

  @MainActor static func apply(_ presentation: Presentation, to view: NSTextView) {
    if presentation == .concealed, view.window?.firstResponder === view {
      view.window?.makeFirstResponder(nil)
    }
    let concealed = presentation == .concealed
    if view.isHidden != concealed { view.isHidden = concealed }
  }
}
