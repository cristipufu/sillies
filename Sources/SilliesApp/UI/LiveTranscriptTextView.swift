import AppKit
import SwiftUI

/// Native text scrolling avoids SwiftUI's repeated measurement of a growing selectable Text.
struct LiveTranscriptTextView: NSViewRepresentable {
  enum Presentation { case visible, concealed }
  @Environment(\.silliesTheme) private var theme
  let text: String
  @Binding var followsLive: Bool
  var presentation: Presentation = .visible

  func makeNSView(context: Context) -> TranscriptScrollView {
    TranscriptScrollView()
  }

  func updateNSView(_ view: TranscriptScrollView, context: Context) {
    if presentation == .concealed, view.window?.firstResponder === view.textView {
      view.window?.makeFirstResponder(nil)
    }
    view.isHidden = presentation == .concealed
    view.onFollowModeChange = { followsLive = $0 == .live }
    view.applyTheme(theme)
    view.update(text: text, followMode: followsLive ? .live : .reading)
  }

  static func dismantleNSView(_ view: TranscriptScrollView, coordinator: ()) {
    view.stopObserving()
  }
}
