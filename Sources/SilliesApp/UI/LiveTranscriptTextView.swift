import AppKit
import SwiftUI

/// Native text scrolling avoids SwiftUI's repeated measurement of a growing selectable Text.
struct LiveTranscriptTextView: NSViewRepresentable {
  let text: String
  @Binding var followsLive: Bool

  func makeNSView(context: Context) -> TranscriptScrollView {
    TranscriptScrollView()
  }

  func updateNSView(_ view: TranscriptScrollView, context: Context) {
    view.onFollowModeChange = { followsLive = $0 == .live }
    view.update(text: text, followMode: followsLive ? .live : .reading)
  }

  static func dismantleNSView(_ view: TranscriptScrollView, coordinator: ()) {
    view.stopObserving()
  }
}
