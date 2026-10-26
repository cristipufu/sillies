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
