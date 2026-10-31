import SilliesAudio

extension AudioSessionUpdateDelivery {
  convenience init(receive: @escaping @MainActor @Sendable (AudioCaptureUpdate) -> Void) {
    self.init(schedule: { MainRunLoopDelivery.perform($0) }, receive: receive)
  }
}
