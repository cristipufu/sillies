import Foundation
import SilliesCore
import Synchronization
import Testing

@testable import SilliesVoicePlayback

@Test func playbackAudibilitySkipsLeadingSilenceAndReportsOnlyTheFirstRenderedSample() {
  let times = Mutex<[TimeInterval]>([])
  let probe = VoiceAudibilityProbe { time in times.withLock { $0.append(time) } }
  probe.observe(.init(samples: [0, 0, 0], sampleRate: 48_000, startTime: 100))
  probe.observe(.init(samples: [.nan], sampleRate: 48_000, startTime: 100))
  #expect(times.withLock { $0.isEmpty })
  let frame = AudioRenderFrame(samples: [0, 0, 0.1], sampleRate: 48_000, startTime: 101)
  DispatchQueue.concurrentPerform(iterations: 100) { _ in probe.observe(frame) }
  #expect(times.withLock { $0 } == [101 + 2.0 / 48_000])
}
