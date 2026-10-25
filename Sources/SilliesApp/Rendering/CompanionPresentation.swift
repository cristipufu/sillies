import AppKit
import QuartzCore
import SilliesCore

/// Owns visibility and transition cancellation; geometry and behavior never wait for a clip.
@MainActor
final class CompanionPresentation {
  private enum Phase { case hidden, entering, visible, exiting }
  private let panel: CompanionPanel
  private let view: CompanionView
  private let profile: CharacterTransitions
  private let library: TransitionLibrary
  private var phase = Phase.hidden
  private var generation = 0

  init(
    panel: CompanionPanel, view: CompanionView,
    profile: CharacterTransitions, library: TransitionLibrary
  ) {
    self.panel = panel
    self.view = view
    self.profile = profile
    self.library = library
  }

  func show(reattached: Bool = false, reducedMotion: Bool) {
    let wasHidden = phase == .hidden
    guard wasHidden || phase == .exiting || reattached else { return }
    let kind: TransitionKind = wasHidden || phase == .exiting ? .enter : .reattach
    if !panel.isVisible { panel.orderFrontRegardless() }
    play(kind, reducedMotion: reducedMotion, startsHidden: wasHidden || reattached)
  }

  func hide(immediately: Bool = false) {
    guard phase != .hidden else { return }
    panel.ignoresMouseEvents = true
    if immediately {
      generation += 1
      view.presentationLayer.removeAllAnimations()
      finishHiding()
    } else if phase != .exiting {
      play(.exit, reducedMotion: false)
    }
  }

  func close() {
    hide(immediately: true)
    panel.close()
  }

  private func play(
    _ kind: TransitionKind, reducedMotion: Bool, startsHidden: Bool = false
  ) {
    let layer = view.presentationLayer
    let presented = layer.presentation() ?? layer
    let context = TransitionContext(
      kind: kind, duration: profile.definition(for: kind).duration,
      fromOpacity: startsHidden ? 0 : Double(presented.opacity),
      fromScale: startsHidden ? 0.84 : Double(presented.transform.m11))
    generation += 1
    let token = generation
    phase = kind == .exit ? .exiting : .entering
    layer.removeAllAnimations()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.opacity = Float(context.targetOpacity)
    layer.transform = CATransform3DIdentity
    let animation =
      reducedMotion ? nil : library.make(profile.definition(for: kind).animation, context: context)
    if let animation {
      CATransaction.setCompletionBlock { [weak self] in
        Task { @MainActor [weak self] in self?.complete(kind, token: token) }
      }
      layer.add(animation, forKey: "presentation")
    }
    CATransaction.commit()
    if animation == nil { complete(kind, token: token) }
  }

  private func complete(_ kind: TransitionKind, token: Int) {
    guard generation == token else { return }
    if kind == .exit { finishHiding() } else { phase = .visible }
  }

  private func finishHiding() {
    phase = .hidden
    panel.orderOut(nil)
    view.rig.resetPose()
  }
}
