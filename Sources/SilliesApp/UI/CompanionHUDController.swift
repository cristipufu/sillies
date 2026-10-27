import AppKit
import SilliesCore
import SwiftUI

@MainActor
final class CompanionHUDController {
  private static let fallbackSize = CGSize(width: 340, height: 64)
  private static let measurementProposal = CGSize(
    width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
  private static let minPanelWidth: CGFloat = 220
  private static let minPanelHeight: CGFloat = 52
  private static let headTopOffsetFactor: Double = 0.78
  private static let horizontalScreenInset: CGFloat = 6
  private static let bottomScreenInset: CGFloat = 6
  private static let topScreenInset: CGFloat = 2
  nonisolated private static let asciiZeroScalar: UInt32 = 0x30
  nonisolated private static let asciiNineScalar: UInt32 = 0x39

  private enum LayoutKey: Equatable {
    case hidden
    case active(skill: CompanionSkillKind, appName: String, normalizedDetail: String)
    case completed(skill: CompanionSkillKind, appName: String, summary: String)

    init(_ state: CompanionBindingState) {
      switch state {
      case .followingFocusedWindow:
        self = .hidden
      case .active(let target, let skill, _, let statusDetail, _):
        self = .active(
          skill: skill, appName: target.appName,
          normalizedDetail: Self.normalizeMonospacedDigits(statusDetail))
      case .completed(let target, let skill, let summary, _, _):
        self = .completed(skill: skill, appName: target.appName, summary: summary)
      }
    }

    /// Status labels use `.monospacedDigit()`, so digit-only timer changes (`00:12` -> `00:13`)
    /// preserve exact glyph width while any text or character change invalidates cached sizing.
    private static func normalizeMonospacedDigits(_ text: String) -> String {
      var scalars = String.UnicodeScalarView()
      scalars.reserveCapacity(text.unicodeScalars.count)
      for scalar in text.unicodeScalars {
        if scalar.value >= CompanionHUDController.asciiZeroScalar
          && scalar.value <= CompanionHUDController.asciiNineScalar
        {
          scalars.append("0")
        } else {
          scalars.append(scalar)
        }
      }
      return String(scalars)
    }
  }

  let model = CompanionHUDModel()
  private var panel: SkillFloatingPanel?
  private var hostingController: NSHostingController<CompanionHUDView>?
  private var lastLayoutKey: LayoutKey?
  private var cachedPanelSize: CGSize?
  private(set) var layoutMeasurements = 0
  var windowNumber: Int? { panel?.windowNumber }
  var isVisible: Bool { panel?.isVisible == true }
  var currentPanelSize: CGSize? { panel?.frame.size }

  func update(
    state: CompanionBindingState, companionPoint: CGPoint, characterSize: Double,
    visibleFrame: CGRect
  ) {
    updateModel(state)
    guard state.isBound else {
      hide()
      return
    }
    ensurePanelCreated(for: state)
    updatePanelLevel(for: state)
    let panelSize = resolvePanelSize(for: state)
    let frame = clampedFrame(
      for: panelSize, companionPoint: companionPoint, characterSize: characterSize,
      visibleFrame: visibleFrame)
    if panel?.frame != frame { panel?.setFrame(frame, display: false) }
    if panel?.isVisible != true {
      panel?.orderFrontRegardless()
    }
  }

  private func updateModel(_ state: CompanionBindingState) {
    guard model.state != state else { return }
    model.state = state
    hostingController?.rootView = CompanionHUDView(model: model, state: state)
  }

  func hide() {
    if panel?.isVisible == true { panel?.orderOut(nil) }
  }

  func close() {
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
    hostingController = nil
    lastLayoutKey = nil
    cachedPanelSize = nil
  }

  private func ensurePanelCreated(for state: CompanionBindingState) {
    guard panel == nil else { return }
    let host = NSHostingController(rootView: CompanionHUDView(model: model, state: state))
    // This controller owns the panel frame; avoid SwiftUI's extra minimum/maximum probes.
    host.sizingOptions = []
    let created = SkillFloatingPanel(
      contentRect: CGRect(origin: .zero, size: Self.fallbackSize),
      ignoresMouseEvents: false,
      level: CompanionPanel.hudLevel(forWindowLayer: state.boundTarget?.windowLayer ?? 0))
    created.contentViewController = host
    hostingController = host
    panel = created
  }

  private func updatePanelLevel(for state: CompanionBindingState) {
    let targetHUDLevel = CompanionPanel.hudLevel(
      forWindowLayer: state.boundTarget?.windowLayer ?? 0)
    if panel?.level != targetHUDLevel {
      panel?.level = targetHUDLevel
    }
  }

  private func resolvePanelSize(for state: CompanionBindingState) -> CGSize {
    let key = LayoutKey(state)
    if key == lastLayoutKey, let cachedPanelSize {
      return cachedPanelSize
    }
    layoutMeasurements += 1
    let fitting =
      hostingController?.sizeThatFits(in: Self.measurementProposal) ?? Self.fallbackSize
    let measured = CGSize(
      width: max(Self.minPanelWidth, ceil(fitting.width)),
      height: max(Self.minPanelHeight, ceil(fitting.height)))
    lastLayoutKey = key
    cachedPanelSize = measured
    return measured
  }

  private func clampedFrame(
    for panelSize: CGSize, companionPoint: CGPoint, characterSize: Double, visibleFrame: CGRect
  ) -> CGRect {
    let headTopOffset = characterSize * Self.headTopOffsetFactor
    let unclampedX = companionPoint.x - panelSize.width / 2
    let clampedX = min(
      max(unclampedX, visibleFrame.minX + Self.horizontalScreenInset),
      visibleFrame.maxX - panelSize.width - Self.horizontalScreenInset)
    let preferredY = companionPoint.y + headTopOffset
    let clampedY = min(
      max(preferredY, visibleFrame.minY + Self.bottomScreenInset),
      visibleFrame.maxY - panelSize.height - Self.topScreenInset)
    return CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: panelSize)
  }
}
