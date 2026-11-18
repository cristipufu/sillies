import Foundation

/// Accessibility-verified identity and geometry, in top-left screen coordinates.
public struct CallSpeakerTile: Equatable, Sendable {
  public enum Audio: Equatable, Sendable { case muted, unmuted }
  public let name: CallSpeakerName
  public let frame: CGRect
  public let audio: Audio

  public init(name: CallSpeakerName, frame: CGRect, audio: Audio) {
    self.name = name
    self.frame = frame
    self.audio = audio
  }
}
