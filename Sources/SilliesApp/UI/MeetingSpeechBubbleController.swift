import AppKit
import QuartzCore
import SilliesCore
import SwiftUI

/// One nonactivating, click-through bubble. Geometry follows native placement; only new ideas animate.
@MainActor
final class MeetingSpeechBubbleController {
  private let appearance: ThemeEnvironment
  init(appearance: ThemeEnvironment) {
    self.appearance = appearance
  }

  struct Placement {
    let anchor: CompanionSpeechBubbleLayout.Anchor
    let companionWindow: NSWindow
    var controlsFrame: CGRect?
  }
  private struct MeasurementKey: Equatable {
    let suggestionID: UUID
    let availableWidth: CGFloat
  }
  private static let transitionDuration: TimeInterval = 0.24
  private static let maximumWidth: CGFloat = 300
  private static let initialSize = CGSize(width: maximumWidth, height: 1)
  private var panel: SkillFloatingPanel?
  private var host: ThemedHostingController<MeetingSpeechBubbleView>?
  private var suggestionID: UUID?
  private var background: CompanionSpeechBubbleBackground?
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
    guard prepare(suggestion: suggestion, placement: placement) else { return }
    guard let panel else { return }
    let wasVisible = panel.isVisible
    guard let companionID = placement.companionWindow.windowServerID else {
      hide()
      return
    }
    panel.order(.above, relativeTo: Int(companionID))
    if changed || !wasVisible { animateAppearance() }
  }

  /// Layout and stacking policy can be verified without presenting a native window.
  @discardableResult
  func prepare(suggestion: MeetingSuggestion, placement: Placement) -> Bool {
    updateContent(suggestion)
    let size = resolveSize(for: suggestion, visibleFrame: placement.anchor.visibleFrame)
    let layout: CompanionSpeechBubbleLayout
    if let controlsFrame = placement.controlsFrame {
      guard
        let available = CompanionSpeechBubbleLayout(
          anchor: placement.anchor, size: size, avoiding: controlsFrame)
      else {
        hide()
        return false
      }
      layout = available
    } else {
      layout = CompanionSpeechBubbleLayout(anchor: placement.anchor, size: size)
    }
    updateGeometry(layout, level: placement.companionWindow.level)
    return true
  }

  private func updateContent(_ suggestion: MeetingSuggestion) {
    guard suggestionID != suggestion.id else { return }
    let view = MeetingSpeechBubbleView(suggestion: suggestion)
    if let host { host.content = view } else { createPanel(view) }
    suggestionID = suggestion.id
    contentUpdates += 1
  }

  private func resolveSize(for suggestion: MeetingSuggestion, visibleFrame: CGRect) -> CGSize {
    let width = min(
      Self.maximumWidth, CompanionSpeechBubbleLayout.availableSize(in: visibleFrame).width)
    let key = MeasurementKey(suggestionID: suggestion.id, availableWidth: width)
    guard measurementKey != key, let host else { return measuredSize }
    let fitting = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    measuredSize = CGSize(width: min(width, ceil(fitting.width)), height: ceil(fitting.height))
    measurementKey = key
    layoutMeasurements += 1
    return measuredSize
  }

  private func updateGeometry(_ layout: CompanionSpeechBubbleLayout, level: NSWindow.Level) {
    guard let panel else { return }
    if panel.level != level { panel.level = level }
    if panel.frame != layout.frame { panel.setFrame(layout.frame, display: false) }
    background?.update(layout)
  }

  private func createPanel(_ view: MeetingSpeechBubbleView) {
    let host = ThemedHostingController(rootView: view, appearance: appearance)
    host.sizingOptions = []
    let panel = SkillFloatingPanel(
      contentRect: CGRect(origin: .zero, size: Self.initialSize),
      ignoresMouseEvents: true)
    let background = CompanionSpeechBubbleBackground(
      frame: panel.contentRect(forFrameRect: panel.frame))
    appearance.observe(background) { view, palette in view.applyTheme(palette) }
    host.view.frame = background.bounds
    host.view.autoresizingMask = [.width, .height]
    host.view.wantsLayer = true
    background.addSubview(host.view)
    panel.contentView = background
    self.background = background
    self.host = host
    self.panel = panel
    if let id = panel.windowServerID {
      trackingExclusion = WindowTrackingExclusions.shared.register(id)
    }
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
