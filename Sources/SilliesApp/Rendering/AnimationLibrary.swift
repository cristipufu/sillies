import AppKit
import QuartzCore
import SilliesCore

/// Resolves reusable clips, pose variants, and optional character-specific overrides.
@MainActor
final class AnimationLibrary {
  typealias Clip = @MainActor (CharacterRig) -> Void
  private var clips: [AnimationID: Clip] = [:]
  private var characterClips: [String: [AnimationID: Clip]] = [:]
  private var reducedMotionClips: [AnimationID: Clip] = [:]
  private var characterReducedMotionClips: [String: [AnimationID: Clip]] = [:]
  private var poseVariants: [AttachmentPose: [AnimationID: AnimationID]] = [:]

  init() {
    BuiltinAnimations.register(in: self)
    FrogAnimations.register(in: self)
    RobotAnimations.register(in: self)
    GhostAnimations.register(in: self)
    OctopusAnimations.register(in: self)
    MushroomAnimations.register(in: self)
    AxolotlAnimations.register(in: self)
    PenguinAnimations.register(in: self)
    DragonAnimations.register(in: self)
    HedgehogAnimations.register(in: self)
    BunnyAnimations.register(in: self)
  }

  /// Signature actions have a static expression and a safe fixed-grip side variant.
  func registerSignature(_ id: AnimationID, characterID: String, clip: @escaping Clip) {
    register(id, characterID: characterID, clip: clip)
    registerReducedMotion(id, characterID: characterID) { rig in
      rig.eyes.opacity = 0
      rig.closedEyes.opacity = 1
      rig.delight.opacity = 1
    }
    for pose in [AttachmentPose.hangingLeft, .hangingRight] {
      registerVariant(id, pose: pose, clip: .hangCatch)
    }
  }

  func register(_ id: AnimationID, characterID: String? = nil, clip: @escaping Clip) {
    if let characterID {
      characterClips[characterID, default: [:]][id] = clip
    } else {
      clips[id] = clip
    }
  }

  func registerReducedMotion(_ id: AnimationID, characterID: String? = nil, clip: @escaping Clip) {
    if let characterID {
      characterReducedMotionClips[characterID, default: [:]][id] = clip
    } else {
      reducedMotionClips[id] = clip
    }
  }

  func registerVariant(_ id: AnimationID, pose: AttachmentPose, clip: AnimationID) {
    poseVariants[pose, default: [:]][id] = clip
  }

  func contains(
    _ id: AnimationID, characterID: String, pose: AttachmentPose = .standing
  ) -> Bool {
    let resolved = poseVariants[pose]?[id] ?? id
    return characterClips[characterID]?[resolved] != nil || clips[resolved] != nil
  }

  func apply(
    _ state: BehaviorState, to rig: CharacterRig, characterID: String,
    reducedMotion: Bool
  ) {
    rig.resetBehaviorPose()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let id = poseVariants[rig.attachmentPose]?[state.animation] ?? state.animation
    if reducedMotion {
      let staticClip =
        characterReducedMotionClips[characterID]?[id]
        ?? characterReducedMotionClips[characterID]?[state.animation]
        ?? reducedMotionClips[id]
        ?? reducedMotionClips[state.animation]
      staticClip?(rig)
    } else {
      let clip = characterClips[characterID]?[id] ?? clips[id] ?? clips[.idle]
      clip?(rig)
    }
    CATransaction.commit()
  }
}
