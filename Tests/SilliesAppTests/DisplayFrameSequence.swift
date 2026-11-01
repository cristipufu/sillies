import AppKit
import QuartzCore
import Testing

@testable import SilliesApp

/// Native panel updates need AppKit's event loop and a commit between display frames.
@MainActor
final class DisplayFrameSequence: NSObject {
  private static let timeoutSeconds: Double = 20
  private static let initialPresentationFrames = 8
  private static let eventPollInterval: TimeInterval = 0.01
  private let count: Int
  private let operation: (Int) -> Void
  private var index = 0
  private var timedOut = false
  private var link: CADisplayLink?

  private init(count: Int, operation: @escaping (Int) -> Void) {
    self.count = count
    self.operation = operation
  }

  /// Let newly created native panels finish their initial WindowServer presentation before
  /// measuring manipulation. Otherwise their first CA fence is charged to the third resize.
  static func presentCreatedWindows() throws {
    try run(count: initialPresentationFrames) { _ in }
  }

  static func run(count: Int, operation: @escaping (Int) -> Void) throws {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let screen = try #require(NSScreen.main ?? NSScreen.screens.first)
    let sequence = DisplayFrameSequence(count: count, operation: operation)
    sequence.start(on: screen)
    let watchdog = sequence.makeWatchdog()
    defer {
      watchdog.cancel()
      sequence.link?.invalidate()
    }
    sequence.pumpEvents(application)
    #expect(!sequence.timedOut)
    #expect(sequence.index == count)
  }

  private func start(on screen: NSScreen) {
    let link = screen.displayLink(target: self, selector: #selector(frame))
    let maximum = Float(screen.maximumFramesPerSecond)
    link.preferredFrameRateRange = CAFrameRateRange(
      minimum: maximum, maximum: maximum, preferred: maximum)
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  private func makeWatchdog() -> DispatchSourceTimer {
    let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
    timer.schedule(deadline: .now() + Self.timeoutSeconds)
    timer.setEventHandler { @Sendable [weak self] in
      MainRunLoopDelivery.perform { [weak self] in
        self?.timedOut = true
        self?.stop()
      }
    }
    timer.resume()
    return timer
  }

  @objc private func frame() {
    index += 1
    operation(index)
    if index >= count { stop() }
  }

  private func pumpEvents(_ application: NSApplication) {
    // NSApp.stop() also stops the run loop used by Swift's async main, which can exit
    // the test process with status zero before the remaining cases execute.
    while index < count, !timedOut {
      autoreleasepool {
        if let event = application.nextEvent(
          matching: .any,
          until: Date().addingTimeInterval(Self.eventPollInterval), inMode: .default, dequeue: true)
        {
          application.sendEvent(event)
        }
        application.updateWindows()
      }
    }
  }

  private func stop() {
    link?.invalidate()
    link = nil
  }
}

@Test(arguments: 0..<3) @MainActor func displayFrameSequenceReturnsWithoutStoppingTheTestRun(
  _ iteration: Int
) throws {
  var frames: [Int] = []
  try DisplayFrameSequence.run(count: 2) { frames.append($0) }
  #expect(frames == [1, 2], "Repeated run \(iteration) must return to the test runner")
}
