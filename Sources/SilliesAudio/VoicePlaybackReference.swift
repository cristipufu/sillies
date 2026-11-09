import Foundation
import SilliesCore
import Synchronization

/// A bounded handoff from the render callback. Resampling and echo cancellation happen on capture's worker.
package final class VoicePlaybackReference: Sendable {
  struct Drain {
    let frames: [AudioRenderFrame]
    let droppedFrames: Int
    let rejectedFrames: Int
  }
  private static let maximumSamples = 192_000
  // Device render quanta are much smaller than the old 100 ms tap batches. Preserve the
  // sample budget when capture is briefly busy without allowing unbounded packet overhead.
  private static let maximumFrames = 512
  private struct State {
    var active = false
    var frames: [AudioRenderFrame] = []
    var samples = 0
    var droppedFrames = 0
    var rejectedFrames = 0
  }
  private let state = Mutex(State())
  package init() {}
  package func start() { state.withLock { $0 = State(active: true) } }
  package func stop() { state.withLock { $0 = State() } }
  package func append(_ frame: AudioRenderFrame) {
    guard frame.startTime.isFinite, frame.startTime >= 0,
      (8_000...192_000).contains(frame.sampleRate),
      !frame.samples.isEmpty, frame.samples.count <= Self.maximumSamples
    else {
      state.withLock {
        if $0.active, $0.rejectedFrames < Int.max { $0.rejectedFrames += 1 }
      }
      return
    }
    state.withLock { state in
      guard state.active else { return }
      while state.frames.count >= Self.maximumFrames
        || state.samples + frame.samples.count > Self.maximumSamples
      {
        state.samples -= state.frames.removeFirst().samples.count
        if state.droppedFrames < Int.max { state.droppedFrames += 1 }
      }
      state.frames.append(frame)
      state.samples += frame.samples.count
    }
  }
  func drain() -> Drain {
    state.withLock {
      let result = Drain(
        frames: $0.frames, droppedFrames: $0.droppedFrames, rejectedFrames: $0.rejectedFrames)
      $0.frames.removeAll(keepingCapacity: true)
      $0.samples = 0
      $0.droppedFrames = 0
      $0.rejectedFrames = 0
      return result
    }
  }
}
