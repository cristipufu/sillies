import Foundation

/// Acoustic turn boundaries use sample durations, never UI timers or recognizer callback timing.
public struct VoiceTurnEndpoint {
  public enum Event { case began, ended }
  private static let minimumSpeech: TimeInterval = 0.18
  private static let onsetGap: TimeInterval = 0.08
  private static let endingSilence: TimeInterval = 0.9
  private var speech: TimeInterval = 0
  private var silence: TimeInterval = 0
  private var hasBegun = false
  public init() {}

  public mutating func consume(isSpeech: Bool, duration: TimeInterval) -> Event? {
    guard duration.isFinite, duration > 0, duration <= 0.1 else { return nil }
    if isSpeech {
      speech += duration
      silence = 0
      if !hasBegun, speech >= Self.minimumSpeech {
        hasBegun = true
        return .began
      }
    } else {
      silence += duration
      if hasBegun, silence >= Self.endingSilence {
        self = Self()
        return .ended
      }
      if !hasBegun, silence >= Self.onsetGap { speech = 0 }
    }
    return nil
  }
}
