import Foundation

/// Pairs capture-time samples, not callback arrival order. Storage is fixed and gaps are silence.
public struct MeetingAudioTimeline {
  public enum Source { case meeting, microphone }
  public enum Failure: Error { case invalidTime, discontinuity }
  public struct Frame {
    public let startTime: TimeInterval
    public let meeting: [Float]
    public let microphone: [Float]
    public let validSamples: Int
  }
  public static let sampleRate = 16_000
  public static let frameSamples = 160
  public static let callbackHoldback: TimeInterval = 0.12
  private static let capacity = sampleRate * 2
  private static let holdbackSamples = Int(callbackHoldback * Double(sampleRate))
  private var meeting = SampleRing(capacity: capacity)
  private var microphone = SampleRing(capacity: capacity)
  private var origin: TimeInterval?
  private var cursor = 0
  private var end = 0
  private var hasEmitted = false

  public init() {}

  public mutating func append(_ samples: [Float], source: Source, at time: TimeInterval) throws {
    guard !samples.isEmpty else { return }
    guard time.isFinite, time >= 0 else { throw Failure.invalidTime }
    if origin == nil { origin = time }
    guard let origin else { return }
    let relative = (time - origin) * Double(Self.sampleRate)
    guard relative.isFinite, abs(relative) < Double(Int.max / 2) else {
      throw Failure.invalidTime
    }
    let start = Int(relative.rounded())
    guard samples.count <= Self.capacity, start + samples.count - cursor <= Self.capacity,
      start >= cursor - Self.capacity
    else { throw Failure.discontinuity }
    if !hasEmitted { cursor = min(cursor, start) }
    end = max(end, start + samples.count)
    switch source {
    case .meeting: meeting.insert(samples, at: start)
    case .microphone: microphone.insert(samples, at: start)
    }
  }

  public mutating func nextReadyFrame() -> Frame? {
    guard cursor + Self.frameSamples <= end - Self.holdbackSamples else { return nil }
    return takeFrame(validSamples: Self.frameSamples)
  }

  public mutating func nextFinalFrame() -> Frame? {
    guard cursor < end else { return nil }
    return takeFrame(validSamples: min(Self.frameSamples, end - cursor))
  }

  private mutating func takeFrame(validSamples: Int) -> Frame? {
    guard let origin else { return nil }
    let frame = Frame(
      startTime: origin + Double(cursor) / Double(Self.sampleRate),
      meeting: meeting.read(at: cursor, count: Self.frameSamples),
      microphone: microphone.read(at: cursor, count: Self.frameSamples), validSamples: validSamples)
    cursor += Self.frameSamples
    hasEmitted = true
    return frame
  }

  private struct SampleRing {
    private var samples: [Float]
    private var positions: [Int]
    init(capacity: Int) {
      samples = .init(repeating: 0, count: capacity)
      positions = .init(repeating: .min, count: capacity)
    }
    mutating func insert(_ values: [Float], at start: Int) {
      for (offset, value) in values.enumerated() {
        let position = start + offset
        let index = slot(position)
        samples[index] = value.isFinite ? value : 0
        positions[index] = position
      }
    }
    func read(at start: Int, count: Int) -> [Float] {
      (start..<(start + count)).map { position in
        let index = slot(position)
        return positions[index] == position ? samples[index] : 0
      }
    }
    private func slot(_ position: Int) -> Int {
      let remainder = position % samples.count
      return remainder >= 0 ? remainder : remainder + samples.count
    }
  }
}
