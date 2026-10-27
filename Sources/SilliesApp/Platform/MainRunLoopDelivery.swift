import AppKit

/// Delivers finite completions during native tracking and AppKit's modal termination loop too.
enum MainRunLoopDelivery {
  static func perform(_ operation: @escaping @MainActor @Sendable () -> Void) {
    let modes: [CFString] = [
      CFRunLoopMode.commonModes.rawValue,
      CFRunLoopMode.defaultMode.rawValue,
      RunLoop.Mode.modalPanel.rawValue as CFString,
      RunLoop.Mode.eventTracking.rawValue as CFString,
    ]
    let mainLoop = CFRunLoopGetMain()
    CFRunLoopPerformBlock(mainLoop, modes as CFArray) {
      MainActor.assumeIsolated { operation() }
    }
    CFRunLoopWakeUp(mainLoop)
  }
}
