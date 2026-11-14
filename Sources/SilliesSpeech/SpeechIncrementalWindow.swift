import Foundation

/// Keeps sample identity across overlapping windows, with a fixed bound on native history.
package struct SpeechIncrementalWindow {
  package enum Action { case restart, append }
  package struct Update {
    package let action: Action
    package let samples: [Float]
    package let phase: SpeechWindowPosition.Phase
    package let windowOffset: TimeInterval
  }
  private static let maximumEpisodeDuration: TimeInterval = 60
  private static let maximumEpisodeSamples = Int64(
    maximumEpisodeDuration * SpeechWindowBuffer.sampleRate)
  private var origin: Int64?
  private var windowStart: Int64?
  private var consumedThrough: Int64 = 0
  private var phase = SpeechWindowPosition.Phase.complete
  private var inputGain: Float = 1

  package init() {}

  package mutating func advance(_ request: SpeechWindowRequest, inputGain: Float = 1) throws
    -> Update
  {
    let start = try Self.samplePosition(request.window?.start ?? 0)
    guard Int64(request.samples.count) <= Self.maximumEpisodeSamples else {
      throw SpeechError.invalidAudioFormat
    }
    let (end, overflow) = start.addingReportingOverflow(Int64(request.samples.count))
    guard !overflow, inputGain.isFinite, inputGain > 0 else { throw SpeechError.invalidAudioFormat }
    let sameWindow = windowStart == start
    let overlapsBoundary =
      phase == .boundary && start >= (windowStart ?? start) && start <= consumedThrough
    let withinEpisode = origin.map { end >= $0 && end - $0 <= Self.maximumEpisodeSamples } ?? false
    let restart =
      phase == .complete || request.window == nil || self.inputGain != inputGain
      || !withinEpisode || (!sameWindow && !overlapsBoundary) || end < consumedThrough
    if restart {
      origin = start
      consumedThrough = start
    }
    let offset = Int(min(Int64(request.samples.count), max(0, consumedThrough - start)))
    let sourceOrigin = origin ?? start
    consumedThrough = max(consumedThrough, end)
    windowStart = start
    phase = request.window?.phase ?? .complete
    self.inputGain = inputGain
    return Update(
      action: restart ? .restart : .append, samples: Array(request.samples.dropFirst(offset)),
      phase: phase, windowOffset: Double(start - sourceOrigin) / SpeechWindowBuffer.sampleRate)
  }

  private static func samplePosition(_ time: TimeInterval) throws -> Int64 {
    guard time.isFinite, time >= 0,
      let sample = Int64(exactly: (time * SpeechWindowBuffer.sampleRate).rounded())
    else { throw SpeechError.invalidAudioFormat }
    return sample
  }

  package mutating func reset() { self = Self() }
}
