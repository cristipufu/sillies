import Foundation

/// One explicit voice conversation keeps its microphone live, but drains recognition after each turn.
package protocol ConversationCapture: AnyObject, Sendable {
  func start()
  /// Delivers the detached utterance once. It is not repeated in the result of `finish`.
  func finishTurn(completion: @escaping @Sendable (AudioCaptureResult) -> Void)
  /// Stops the device and joins all drains; returns only words not detached by `finishTurn`.
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void)
}

package typealias ConversationCaptureFactory =
  @Sendable (
    AudioCaptureConfiguration, @escaping @Sendable (AudioCaptureUpdate) -> Void
  ) -> any ConversationCapture
