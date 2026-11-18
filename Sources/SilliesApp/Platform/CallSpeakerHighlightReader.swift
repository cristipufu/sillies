import Foundation

/// Serial admission also covers native captures that have not completed after cancellation.
actor CallSpeakerHighlightReader: CallSpeakerVisualReading {
  private let capture: any CallSpeakerImageCapturing
  private var isReading = false
  private var isStopped = false

  init(capture: any CallSpeakerImageCapturing) { self.capture = capture }

  func read(_ request: CallSpeakerVisualRequest) async -> CallSpeakerVisualObservation? {
    guard !isStopped, !isReading, !Task.isCancelled else { return nil }
    isReading = true
    defer { isReading = false }
    let capturedAt = ProcessInfo.processInfo.systemUptime
    guard let image = await capture.capture(request), !isStopped, !Task.isCancelled,
      let speaking = request.interpreter.speakers(in: image, layout: request.layout)
    else { return nil }
    return .init(capturedAt: capturedAt, speaking: speaking)
  }

  func stop() async {
    guard !isStopped else { return }
    isStopped = true
    await capture.stop()
  }
}
