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
  private var relocationCompletion: (() -> Void)?

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
    relocationCompletion = nil
    let wasHidden = phase == .hidden
    guard wasHidden || phase == .exiting || reattached else { return }
    let kind: TransitionKind = wasHidden || phase == .exiting ? .enter : .reattach
    if !panel.isVisible { panel.orderFrontRegardless() }
    play(kind, reducedMotion: reducedMotion, startsHidden: wasHidden || reattached)
  }

  func hide(immediately: Bool = false) {
    relocationCompletion = nil
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

  func hideForRelocation(completion: @escaping () -> Void) {
    relocationCompletion = nil
    panel.ignoresMouseEvents = true
    guard phase != .hidden else {
      completion()
      return
    }
    relocationCompletion = completion
    play(.exit, reducedMotion: false, durationLimit: 0.12)
  }

  func close() {
    hide(immediately: true)
    panel.close()
  }

  private func play(
    _ kind: TransitionKind, reducedMotion: Bool, startsHidden: Bool = false,
    durationLimit: Double = .infinity
  ) {
    let layer = view.presentationLayer
    let presented = startsHidden ? nil : layer.presentation()
    let context = TransitionContext(
      kind: kind, duration: min(profile.definition(for: kind).duration, durationLimit),
      fromOpacity: startsHidden ? 0 : Double((presented ?? layer).opacity),
      fromScale: startsHidden ? 0.84 : Double((presented ?? layer).transform.m11))
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
        MainRunLoopDelivery.perform { [weak self] in self?.complete(kind, token: token) }
      }
      layer.add(animation, forKey: "presentation")
    }
    CATransaction.commit()
    if animation == nil { complete(kind, token: token) }
  }

  private func complete(_ kind: TransitionKind, token: Int) {
    guard generation == token else { return }
    if kind == .exit {
      let relocation = relocationCompletion
      relocationCompletion = nil
      finishHiding()
      relocation?()
    } else {
      phase = .visible
    }
  }

  private func finishHiding() {
    phase = .hidden
    panel.orderOut(nil)
    view.rig.resetPose()
  }
}
