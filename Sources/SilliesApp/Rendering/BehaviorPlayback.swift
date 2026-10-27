import SilliesCore

/// Preserves an uninterrupted clip when reconciliation only changes geometry or preferences.
@MainActor
final class BehaviorPlayback {
  private struct Playback: Equatable {
    let state: BehaviorState
    let pose: AttachmentPose
    let reducedMotion: Bool
    let resetGeneration: Int
  }

  private var current: Playback?
  private let rig: CharacterRig
  private let characterID: String

  init(rig: CharacterRig, characterID: String) {
    self.rig = rig
    self.characterID = characterID
  }

  func apply(
    _ state: BehaviorState, library: AnimationLibrary, reducedMotion: Bool
  ) {
    let requested = snapshot(state, reducedMotion: reducedMotion)
    guard current != requested else { return }
    library.apply(state, to: rig, characterID: characterID, reducedMotion: reducedMotion)
    // Applying a new clip may reset the rig, so retain its resulting generation.
    current = snapshot(state, reducedMotion: reducedMotion)
  }

  private func snapshot(_ state: BehaviorState, reducedMotion: Bool) -> Playback {
    Playback(
      state: state, pose: rig.attachmentPose, reducedMotion: reducedMotion,
      resetGeneration: rig.behaviorResetGeneration)
  }
}
