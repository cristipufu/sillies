import AppKit
import QuartzCore
import SilliesCore
import SwiftUI

/// One nonactivating, click-through bubble. Geometry follows native placement; only new ideas animate.
@MainActor
final class MeetingSpeechBubbleController {
  struct Placement {
    let layout: SuggestionBubbleLayout
    let level: NSWindow.Level
    let companionWindowNumber: Int
  }
  private static let transitionDuration: TimeInterval = 0.24
  private var panel: SkillFloatingPanel?
  private var host: NSHostingController<MeetingSpeechBubbleView>?
  private var suggestionID: UUID?
  private var background: MeetingSpeechBubbleBackground?
  private var trackingExclusion: WindowTrackingExclusions.Registration?
  private(set) var contentUpdates = 0
  var isVisible: Bool { panel?.isVisible == true }
  var windowNumber: Int? { panel?.windowNumber }

  func update(suggestion: MeetingSuggestion?, placement: Placement) {
    guard let suggestion else {
      hide()
      return
    }
    let changed = suggestionID != suggestion.id
    let layout = placement.layout
    if changed {
      let view = MeetingSpeechBubbleView(suggestion: suggestion)
      if let host { host.rootView = view } else { createPanel(view) }
      suggestionID = suggestion.id
      contentUpdates += 1
    }
    guard let panel else { return }
    if panel.level != placement.level { panel.level = placement.level }
    if panel.frame != layout.frame { panel.setFrame(layout.frame, display: false) }
    background?.update(layout)
    let wasVisible = panel.isVisible
    panel.order(.above, relativeTo: placement.companionWindowNumber)
    if changed || !wasVisible { animateAppearance() }
  }

  private func createPanel(_ view: MeetingSpeechBubbleView) {
    let host = NSHostingController(rootView: view)
    host.sizingOptions = []
    let panel = SkillFloatingPanel(
      contentRect: CGRect(origin: .zero, size: SuggestionBubbleLayout.size),
      ignoresMouseEvents: true)
    let background = MeetingSpeechBubbleBackground(
      frame: panel.contentRect(forFrameRect: panel.frame))
    host.view.frame = background.bounds
    host.view.autoresizingMask = [.width, .height]
    host.view.wantsLayer = true
    background.addSubview(host.view)
    panel.contentView = background
    self.background = background
    self.host = host
    self.panel = panel
    trackingExclusion = WindowTrackingExclusions.shared.register(UInt32(panel.windowNumber))
  }

  private func animateAppearance() {
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      let layer = host?.view.layer
    else { return }
    // A finite compositor animation; no timer, focus change, or animation-driven SwiftUI state.
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = Self.transitionDuration
    fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(fade, forKey: "suggestionAppearance")
  }

  func hide() {
    if panel?.isVisible == true { panel?.orderOut(nil) }
  }

  func close() {
    hide()
    panel?.close()
    panel = nil
    host = nil
    trackingExclusion = nil
    suggestionID = nil
    background = nil
  }
}
