import AppKit
import QuartzCore
import SilliesCore

/// One compact, input-transparent shared prop for the active scene.
@MainActor
final class PlayfulPropPresentation {
  private let panel = PlayfulPropPanel()
  private let ropeAnchor = PlayfulRopeAnchorPresentation()
  private let root = CALayer()
  private let artwork = PlayfulSharedArtwork()
  private let messageBubble = PlayfulMessageArtwork()
  private var current: PlayfulSceneDefinition.Prop = .none
  private var owner: PlayfulSceneDefinition.Role = .lead
  private var cardSize = CGSize.zero
  private var fixedRopeIsPlaced = false
  private var artworkSize = CGSize.zero
  var isVisible: Bool { panel.isVisible || ropeAnchor.isVisible }
  var windowNumber: Int { panel.windowNumber }
  var previews: [(NSView, CGRect)] { [panel.preview, ropeAnchor.preview].compactMap { $0 } }
  var windowNumbers: Set<Int> {
    (panel.isVisible ? [panel.windowNumber] : Set<Int>()).union(ropeAnchor.windowNumbers)
  }

  init() {
    let view = NSView()
    view.wantsLayer = true
    root.isOpaque = false
    root.backgroundColor = NSColor.clear.cgColor
    view.layer = root
    panel.contentView = view
    root.addSublayer(artwork.root)
    root.addSublayer(messageBubble.layer)
  }

  struct Preparation {
    let prop: PlayfulSceneDefinition.Prop
    let message: String
    let reducedMotion: Bool
    let startedAt: CFTimeInterval
    var owner: PlayfulSceneDefinition.Role = .lead
    var motion: PlayfulSceneMotion? = nil
    var duration: Double = 0
  }

  func prepare(_ request: Preparation) {
    let prop = request.prop
    let owner = request.owner
    guard prop != current || self.owner != owner else { return }
    if [.descentRope, .retractingRope].contains(current),
      [.descentRope, .retractingRope].contains(prop), self.owner == owner
    {
      current = prop
      return
    }
    hide()
    current = prop
    self.owner = owner
    guard prop != .none else { return }
    panel.prepare()
    artwork.prepare(prop, reducedMotion: request.reducedMotion)
    if !request.reducedMotion {
      if prop == .parachute, let motion = request.motion {
        artwork.animateParachute(motion, duration: request.duration)
      }
      PlayfulClipTiming.synchronize(artwork.root, startingAt: request.startedAt)
    }
    cardSize = messageBubble.prepare(
      prop, message: request.message, appearance: panel.effectiveAppearance,
      scale: panel.backingScaleFactor
    )
  }

  func place(
    frames: [PlayfulSceneSession.Frame], plan: PlayfulScenePlan,
    windowLayer: Int, progress: Double = 0
  ) {
    if current == .descentRope, fixedRopeIsPlaced { return }
    guard
      let proposed = PlayfulPropLayout.frame(
        for: .init(
          prop: current, frames: frames,
          plan: plan, textSize: cardSize, owner: owner, progress: progress))
    else {
      panel.hide()
      ropeAnchor.hide()
      return
    }
    let isHeldProp = [.rope, .descentRope, .retractingRope, .parachute].contains(current)
    let level =
      isHeldProp
      ? NSWindow.Level(
        rawValue: CompanionPanel.overlayLevel(
          forWindowLayer: windowLayer, isPickedUp: false
        ).rawValue - 1)
      : CompanionPanel.hudLevel(forWindowLayer: windowLayer)
    let artworkNeedsLayout =
      abs(artworkSize.width - proposed.width) > PlayfulPropPanel.geometryTolerance
      || abs(artworkSize.height - proposed.height) > PlayfulPropPanel.geometryTolerance
      || current == .retractingRope
    if artworkNeedsLayout {
      artworkSize = proposed.size
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      artwork.resize(to: proposed.size)
      if [.descentRope, .retractingRope].contains(current),
        let actor = frames.first(where: { $0.actor.role == owner }),
        let window = plan.window
      {
        artwork.updateRope(
          PlayfulPropLayout.rope(
            in: proposed, actor: actor, window: window,
            retraction: current == .retractingRope ? progress : 0))
        ropeAnchor.place(actor: actor, plan: plan, level: level)
      }
      if current == .plane, let actor = frames.first(where: { $0.actor.role == owner }) {
        artwork.facePlane(
          right: PlayfulPlaneFlight.facesRight(
            origin: actor.actor.participant.position, visible: plan.visibleFrame))
      }
      CATransaction.commit()
    }
    panel.present(frame: proposed, level: level)
    fixedRopeIsPlaced = current == .descentRope
  }

  func hide() {
    fixedRopeIsPlaced = false
    artworkSize = .zero
    messageBubble.hide()
    artwork.hide()
    root.removeAllAnimations()
    panel.hide()
    ropeAnchor.hide()
    current = .none
  }

  func close() {
    hide()
    panel.close()
    ropeAnchor.close()
  }
}
