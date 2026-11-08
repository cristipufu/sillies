import AppKit
import SilliesCore
import SwiftUI

@MainActor
final class CompanionHUDController {
  private let appearance: ThemeEnvironment
  init(appearance: ThemeEnvironment) {
    self.appearance = appearance
  }

  private static let fallbackSize = CGSize(width: 340, height: 64)
  private static let measurementProposal = CGSize(
    width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
  private static let minPanelWidth: CGFloat = 220
  private static let minPanelHeight: CGFloat = 52
  private static let headTopOffsetFactor: Double = 0.68
  private static let horizontalScreenInset: CGFloat = 6
  private static let bottomScreenInset: CGFloat = 6
  private static let topScreenInset: CGFloat = 2
  nonisolated private static let asciiZeroScalar: UInt32 = 0x30
  nonisolated private static let asciiNineScalar: UInt32 = 0x39

  private enum LayoutKey: Equatable {
    case hidden
    case talk(hasNotice: Bool, voiceCredit: String?)
    case active(skill: CompanionSkillKind, appName: String, normalizedDetail: String)
    case completed(skill: CompanionSkillKind, appName: String, summary: String)

    init(_ state: CompanionBindingState) {
      switch state {
      case .followingFocusedWindow:
        self = .hidden
      case .active(let target, let skill, _, let statusDetail, _):
        self = .active(
          skill: skill, appName: (target?.appName ?? String(localized: "Microphone")),
          normalizedDetail: skill.isAudioSession
            ? "audio" : Self.normalizeMonospacedDigits(statusDetail))
      case .completed(let target, let skill, let summary, _, _):
        self = .completed(
          skill: skill, appName: (target?.appName ?? String(localized: "Microphone")),
          summary: summary)
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

  var attachedWindowLayer = 0
  weak var companionWindow: NSWindow?
  let model = CompanionHUDModel()
  private var panel: SkillFloatingPanel?
  private(set) lazy var speechBubble = MeetingSpeechBubbleController(appearance: appearance)
  private var hostingController: ThemedHostingController<CompanionHUDView>?
  private var background: CompanionSpeechBubbleBackground?
  private(set) var bubbleLayout: CompanionSpeechBubbleLayout?
  private var lastLayoutKey: LayoutKey?
  private var cachedPanelSize: CGSize?
  private(set) var layoutMeasurements = 0
  var windowNumber: Int? { panel?.windowNumber }
  var isVisible: Bool { panel?.isVisible == true }
  var currentPanelSize: CGSize? { panel?.frame.size }
  var windowNumbers: Set<Int> { Set([windowNumber, speechBubble.windowNumber].compactMap { $0 }) }

  func configureControls(_ controls: CompanionHUDModel.Controls) { model.configure(controls) }
  func updatePresentation(_ presentation: SkillPresentation) {
    model.updatePresentation(presentation)
  }
  func showsHUD(for state: CompanionBindingState) -> Bool { model.showsHUD(for: state) }

  func update(state: CompanionBindingState, anchor: CompanionSpeechBubbleLayout.Anchor) {
    prepare(state: state, anchor: anchor)
    guard showsHUD(for: state) else { return }
    if let companionWindowID = companionWindow?.windowServerID {
      panel?.order(.above, relativeTo: Int(companionWindowID))
    } else if panel?.isVisible != true {
      panel?.orderFrontRegardless()
    }
    updateSpeechBubble(anchor: anchor)
  }

  /// Updates content and geometry without ordering a window onto the screen.
  func prepare(state: CompanionBindingState, anchor: CompanionSpeechBubbleLayout.Anchor) {
    updateModel(state)
    guard showsHUD(for: state) else {
      hide()
      return
    }
    ensurePanelCreated(for: state)
    updatePanelLevel(for: state)
    let panelSize = resolvePanelSize(for: state)
    let frame: CGRect
    if model.surface(for: state) == .speechBubble {
      let layout = CompanionSpeechBubbleLayout(
        anchor: anchor, size: panelSize, placement: .aboveContact)
      bubbleLayout = layout
      frame = layout.frame
    } else {
      bubbleLayout = nil
      background?.concealArtwork()
      frame = clampedFrame(
        for: panelSize, anchor: anchor)
    }
    if panel?.frame != frame { panel?.setFrame(frame, display: false) }
    if let bubbleLayout { background?.update(bubbleLayout) }
  }

  private func updateSpeechBubble(anchor: CompanionSpeechBubbleLayout.Anchor) {
    guard let companionWindow, let panel else {
      speechBubble.hide()
      return
    }
    speechBubble.update(
      suggestion: model.audioSession?.currentBubbleSuggestion,
      placement: .init(
        anchor: anchor, companionWindow: companionWindow, controlsFrame: panel.frame))
  }

  private func updateModel(_ state: CompanionBindingState) {
    guard model.state != state else { return }
    model.state = state
    hostingController?.content = CompanionHUDView(model: model, state: state)
  }

  func hide() {
    speechBubble.hide()
    if panel?.isVisible == true { panel?.orderOut(nil) }
  }

  func close() {
    speechBubble.close()
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
    hostingController = nil
    background = nil
    bubbleLayout = nil
    lastLayoutKey = nil
    cachedPanelSize = nil
  }

  private func ensurePanelCreated(for state: CompanionBindingState) {
    guard panel == nil else { return }
    let host = ThemedHostingController(
      rootView: CompanionHUDView(model: model, state: state), appearance: appearance)
    // This controller owns the panel frame; avoid SwiftUI's extra minimum/maximum probes.
    host.sizingOptions = []
    let created = SkillFloatingPanel(
      contentRect: CGRect(origin: .zero, size: Self.fallbackSize),
      ignoresMouseEvents: false,
      level: panelLevel(for: state))
    let background = CompanionSpeechBubbleBackground(
      frame: CGRect(origin: .zero, size: Self.fallbackSize))
    appearance.observe(background) { view, palette in view.applyTheme(palette) }
    background.concealArtwork()
    host.view.frame = background.bounds
    host.view.autoresizingMask = [.width, .height]
    host.view.wantsLayer = true
    background.addSubview(host.view)
    created.contentView = background
    self.background = background
    hostingController = host
    panel = created
  }

  private func updatePanelLevel(for state: CompanionBindingState) {
    let targetHUDLevel = panelLevel(for: state)
    if panel?.level != targetHUDLevel {
      panel?.level = targetHUDLevel
    }
  }

  private func panelLevel(for state: CompanionBindingState) -> NSWindow.Level {
    companionWindow?.level
      ?? CompanionPanel.hudLevel(
        forWindowLayer: state.boundTarget?.windowLayer ?? attachedWindowLayer)
  }

  private func resolvePanelSize(for state: CompanionBindingState) -> CGSize {
    let key: LayoutKey
    if case .active(_, .chat, _, _, _) = state,
      let conversation = model.conversation, conversation.mode == .talk
    {
      key = .talk(
        hasNotice: conversation.failure != nil || conversation.notice != nil
          || conversation.history.failure != nil,
        voiceCredit: conversation.voiceAttribution?.text)
    } else {
      key = LayoutKey(state)
    }
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

  private func clampedFrame(for panelSize: CGSize, anchor: CompanionSpeechBubbleLayout.Anchor)
    -> CGRect
  {
    let visibleFrame = anchor.visibleFrame
    let headTopOffset = anchor.characterSize * Self.headTopOffsetFactor
    let unclampedX = anchor.companionPoint.x - panelSize.width / 2
    let clampedX = min(
      max(unclampedX, visibleFrame.minX + Self.horizontalScreenInset),
      visibleFrame.maxX - panelSize.width - Self.horizontalScreenInset)
    let preferredY = anchor.companionPoint.y + headTopOffset
    let clampedY = min(
      max(preferredY, visibleFrame.minY + Self.bottomScreenInset),
      visibleFrame.maxY - panelSize.height - Self.topScreenInset)
    return CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: panelSize)
  }
}
