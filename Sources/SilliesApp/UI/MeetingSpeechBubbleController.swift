import AppKit
import QuartzCore
import SilliesCore
import SwiftUI

/// One nonactivating, click-through bubble. Geometry follows native placement; only new ideas animate.
@MainActor
final class MeetingSpeechBubbleController {
  struct Placement {
    let anchor: SuggestionBubbleLayout.Anchor
    let windowLayer: Int
  }
  private struct MeasurementKey: Equatable {
    let suggestionID: UUID
    let availableWidth: CGFloat
  }
  private static let transitionDuration: TimeInterval = 0.24
  private static let maximumWidth: CGFloat = 300
  private static let initialSize = CGSize(width: maximumWidth, height: 1)
  private var panel: SkillFloatingPanel?
  private var host: NSHostingController<MeetingSpeechBubbleView>?
  private var suggestionID: UUID?
  private var background: MeetingSpeechBubbleBackground?
  private var trackingExclusion: WindowTrackingExclusions.Registration?
  private var measuredSize: CGSize = .zero
  private var measurementKey: MeasurementKey?
  private(set) var contentUpdates = 0
  private(set) var layoutMeasurements = 0
  var isVisible: Bool { panel?.isVisible == true }
  var windowNumber: Int? { panel?.windowNumber }

  func update(suggestion: MeetingSuggestion?, placement: Placement) {
    guard let suggestion else {
      hide()
      return
    }
    let changed = suggestionID != suggestion.id
    updateContent(suggestion)
    guard let panel else { return }
    let layout = SuggestionBubbleLayout(
      anchor: placement.anchor,
      size: resolveSize(for: suggestion, visibleFrame: placement.anchor.visibleFrame))
    updateGeometry(layout, windowLayer: placement.windowLayer)
    let wasVisible = panel.isVisible
    if !wasVisible { panel.orderFrontRegardless() }
    if changed || !wasVisible { animateAppearance() }
  }

  private func updateContent(_ suggestion: MeetingSuggestion) {
    guard suggestionID != suggestion.id else { return }
    let view = MeetingSpeechBubbleView(suggestion: suggestion)
    if let host { host.rootView = view } else { createPanel(view) }
    suggestionID = suggestion.id
    contentUpdates += 1
  }

  private func resolveSize(for suggestion: MeetingSuggestion, visibleFrame: CGRect) -> CGSize {
    let width = min(
      Self.maximumWidth, SuggestionBubbleLayout.availableSize(in: visibleFrame).width)
    let key = MeasurementKey(suggestionID: suggestion.id, availableWidth: width)
    guard measurementKey != key, let host else { return measuredSize }
    let fitting = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    measuredSize = CGSize(width: min(width, ceil(fitting.width)), height: ceil(fitting.height))
    measurementKey = key
    layoutMeasurements += 1
    return measuredSize
  }

  private func updateGeometry(_ layout: SuggestionBubbleLayout, windowLayer: Int) {
    guard let panel else { return }
    let level = CompanionPanel.hudLevel(forWindowLayer: windowLayer)
    if panel.level != level { panel.level = level }
    if panel.frame != layout.frame { panel.setFrame(layout.frame, display: false) }
    background?.update(layout)
  }

  private func createPanel(_ view: MeetingSpeechBubbleView) {
    let host = NSHostingController(rootView: view)
    host.sizingOptions = []
    let panel = SkillFloatingPanel(
      contentRect: CGRect(origin: .zero, size: Self.initialSize),
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
      let layer = background?.layer
    else { return }
    // A finite compositor animation; no timer, focus change, or animation-driven SwiftUI state.
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = Self.transitionDuration
    fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    let lift = CABasicAnimation(keyPath: "transform.translation.y")
    lift.fromValue = 3
    lift.toValue = 0
    lift.duration = Self.transitionDuration
    lift.timingFunction = CAMediaTimingFunction(name: .easeOut)
    let appearance = CAAnimationGroup()
    appearance.animations = [fade, lift]
    appearance.duration = Self.transitionDuration
    layer.add(appearance, forKey: "suggestionAppearance")
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
    measurementKey = nil
    measuredSize = .zero
  }
}
