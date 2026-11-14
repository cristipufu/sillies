/// A source's strongest sample bounds amplification; quieter frames never raise an established gain.
public struct SpeechSignalGain: Sendable {
  private static let targetPeak: Float = 0.125
  private static let maximumGain: Float = 2
  private var sourcePeak: Float = 0
  public init() {}

  public mutating func observe(peak: Float) -> Float? {
    guard peak.isFinite, peak >= 0 else { return nil }
    sourcePeak = max(sourcePeak, peak)
    guard sourcePeak > 0 else { return 1 }
    var gain = Self.maximumGain
    while gain > 1, sourcePeak * gain > Self.targetPeak { gain /= 2 }
    return gain
  }

  public mutating func reset() { self = Self() }
}
