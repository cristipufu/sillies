import AppKit
import QuartzCore
import SilliesCore
import SwiftUI

/// Non-activating floating panel used for the window drop highlight, radial skill wheel, and status HUDs.
/// WindowServer shadow is disabled so SwiftUI renders crisp, unclipped shadows without rectangular backing halos.
@MainActor
final class SkillFloatingPanel: NSPanel {
  private var occlusionExclusion: WindowTrackingExclusions.Registration?
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  init(contentRect: CGRect, ignoresMouseEvents: Bool, level: NSWindow.Level = .statusBar) {
    super.init(
      contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    animationBehavior = .none
    self.level = level
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    self.ignoresMouseEvents = ignoresMouseEvents
    collectionBehavior = CompanionPanel.overlayCollectionBehavior
    occlusionExclusion = WindowTrackingExclusions.transparentOverlays.register(UInt32(windowNumber))
    if CompanionPanel.isRunningUnderUnitTests { alphaValue = 0 }
  }
}

/// Build and render the two shared overlays once, before drag interaction is enabled.
@MainActor
enum SkillOverlayPreparation {
  static let target = WindowTargetCandidate(
    windowID: 0, processID: 0, appName: "Window",
    frame: CGRect(x: 0, y: 0, width: 480, height: 320))

  static func render(_ view: NSView) {
    view.layoutSubtreeIfNeeded()
  }
}

@MainActor @Observable
final class WindowDropHighlightModel {
  var target: WindowTargetCandidate?
  var hoveredSkill: CompanionSkillKind?
}

struct WindowDropHighlightView: View {
  let model: WindowDropHighlightModel

  var body: some View {
    HStack(spacing: 6) {
      if let target = model.target {
        if let skill = model.hoveredSkill {
          Image(systemName: skill.symbolName).font(.system(size: 11, weight: .bold))
          Text("\(skill.title) · \(target.appName)")
            .font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
        } else {
          if let icon = ApplicationIconCache.shared.image(for: target) {
            Image(nsImage: icon).resizable().frame(width: 15, height: 15)
          } else {
            Image(systemName: "macwindow").font(.system(size: 10.5, weight: .semibold))
          }
          Text(target.appName)
            .font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
        }
      }
    }
    .foregroundStyle(model.hoveredSkill != nil ? Color.white : SilliesTheme.ink)
    .padding(.horizontal, 11).padding(.vertical, 5)
    .background(
      Capsule().fill(
        model.hoveredSkill != nil ? SilliesTheme.accent : SilliesTheme.card.opacity(0.97))
    )
    .overlay(
      Capsule().strokeBorder(
        model.hoveredSkill != nil ? Color.white.opacity(0.4) : SilliesTheme.border, lineWidth: 0.8)
    )
    .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
    .padding(12)
  }
}

/// Only the outline uses window-sized geometry; SwiftUI lays out a small, fixed-size badge.
/// Uses a hardware-composited `CALayer` border so WindowServer renders the outline
/// directly without allocating or CPU-rasterizing a window-sized backing bitmap.
@MainActor
private final class WindowDropOutlineView: NSView {
  private static let cornerRadius: CGFloat = 12
  private static let outlineInset: CGFloat = 3
  private static let badgeWidth: CGFloat = 400
  private static let badgeHeight: CGFloat = 56
  private static let badgeTopOffset: CGFloat = 66
  private static let selectedBorderWidth: CGFloat = 3
  private static let unselectedBorderWidth: CGFloat = 2.2
  private static let selectedBorderColor = NSColor(
    srgbRed: 0.52, green: 0.47, blue: 0.77, alpha: 0.95
  ).cgColor
  private static let unselectedBorderColor = NSColor(
    srgbRed: 0.52, green: 0.47, blue: 0.77, alpha: 0.72
  ).cgColor

  private let outline = CALayer()
  let badge: NSHostingView<WindowDropHighlightView>
  var hasHardwareBorderOutline: Bool {
    outline.borderWidth > 0 && outline.cornerRadius == Self.cornerRadius && outline.contents == nil
  }

  init(model: WindowDropHighlightModel) {
    badge = NSHostingView(rootView: WindowDropHighlightView(model: model))
    badge.sizingOptions = []
    badge.frame = CGRect(x: 0, y: 0, width: Self.badgeWidth, height: Self.badgeHeight)
    super.init(frame: SkillOverlayPreparation.target.frame)
    wantsLayer = true
    layer?.addSublayer(outline)
    addSubview(badge)
    outline.backgroundColor = nil
    outline.cornerRadius = Self.cornerRadius
    outline.cornerCurve = .continuous
    updateSelection(false)
  }

  required init?(coder: NSCoder) { nil }

  override func layout() {
    super.layout()
    updateGeometry()
  }

  func updateGeometry() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    outline.frame = bounds.insetBy(dx: Self.outlineInset, dy: Self.outlineInset)
    let width = min(Self.badgeWidth, bounds.width)
    let origin = CGPoint(
      x: ((bounds.width - width) / 2).rounded(),
      y: (bounds.height - Self.badgeTopOffset).rounded())
    if badge.frame.size.width != width || badge.frame.size.height != Self.badgeHeight {
      badge.frame = CGRect(origin: origin, size: CGSize(width: width, height: Self.badgeHeight))
    } else if badge.frame.origin != origin {
      badge.setFrameOrigin(origin)
    }
    CATransaction.commit()
  }

  func updateSelection(_ selected: Bool) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    outline.borderColor = selected ? Self.selectedBorderColor : Self.unselectedBorderColor
    outline.borderWidth = selected ? Self.selectedBorderWidth : Self.unselectedBorderWidth
    CATransaction.commit()
  }
}

/// Highlights the candidate target window underneath a dragged companion.
@MainActor
final class WindowDropHighlightController {
  private static let highlightFrameOutset: CGFloat = -2

  private let model = WindowDropHighlightModel()
  private var panel: SkillFloatingPanel?
  private var outlineView: WindowDropOutlineView?
  private var appliedFrame: CGRect = .zero
  private var appliedProcessID: Int32 = -1
  private var appliedAppName: String = ""
  var windowNumber: Int? { panel?.windowNumber }
  var isVisible: Bool { panel?.isVisible == true }
  var usesHardwareBorderOutline: Bool {
    outlineView?.hasHardwareBorderOutline == true
  }

  func prepare() {
    guard panel == nil else { return }
    let initialFrame = SkillOverlayPreparation.target.frame.integral
    model.target = SkillOverlayPreparation.target
    appliedFrame = initialFrame
    appliedProcessID = SkillOverlayPreparation.target.processID
    appliedAppName = SkillOverlayPreparation.target.appName
    let created = SkillFloatingPanel(
      contentRect: initialFrame, ignoresMouseEvents: true,
      level: CompanionPanel.overlayLevel)
    let view = WindowDropOutlineView(model: model)
    created.contentView = view
    panel = created
    outlineView = view
    view.layoutSubtreeIfNeeded()
    SkillOverlayPreparation.render(view.badge)
  }

  func prestage(target: WindowTargetCandidate?) {
    guard let target else { return }
    applyTarget(target, hoveredSkill: nil)
  }

  func show(target: WindowTargetCandidate, hoveredSkill: CompanionSkillKind?) {
    applyTarget(target, hoveredSkill: hoveredSkill)
    if panel?.isVisible != true { panel?.orderFrontRegardless() }
  }

  func hide() {
    if panel?.isVisible == true { panel?.orderOut(nil) }
  }

  func close() {
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
    outlineView = nil
    appliedFrame = .zero
    appliedProcessID = -1
    appliedAppName = ""
  }

  private func applyTarget(
    _ target: WindowTargetCandidate, hoveredSkill: CompanionSkillKind?
  ) {
    prepare()
    if appliedProcessID != target.processID || appliedAppName != target.appName {
      appliedProcessID = target.processID
      appliedAppName = target.appName
      ApplicationIconCache.shared.prepare(for: target)
      model.target = target
    }
    if model.hoveredSkill != hoveredSkill {
      model.hoveredSkill = hoveredSkill
      outlineView?.updateSelection(hoveredSkill != nil)
    }
    let highlightFrame = target.frame.insetBy(
      dx: Self.highlightFrameOutset, dy: Self.highlightFrameOutset
    ).integral
    guard appliedFrame != highlightFrame else { return }
    let sizeChanged = appliedFrame.size != highlightFrame.size
    appliedFrame = highlightFrame
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if sizeChanged {
      panel?.setFrame(highlightFrame, display: false)
      outlineView?.updateGeometry()
    } else {
      panel?.setFrameOrigin(highlightFrame.origin)
    }
    CATransaction.commit()
  }
}
