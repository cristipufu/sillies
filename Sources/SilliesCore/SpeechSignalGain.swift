/// Peak and analysis-energy bounds limit gain; quieter frames never raise an established gain.
public struct SpeechSignalGain: Sendable {
  public enum Purpose: Sendable { case decoding, detection }
  private static let targetPeak: Float = 0.125
  private static let maximumDecodingGain: Float = 2
  private static let maximumDetectionGain: Float = 16
  private static let detectionRootMeanSquare: Float = 0.024
  private let purpose: Purpose
  private var sourcePeak: Float = 0
  private var sourceRootMeanSquare: Float = 0
  public init(purpose: Purpose = .decoding) { self.purpose = purpose }

  public mutating func observe(peak: Float, rootMeanSquare: Float) -> Float? {
    guard peak.isFinite, peak >= 0, rootMeanSquare.isFinite,
      rootMeanSquare >= 0, rootMeanSquare <= peak
    else { return nil }
    sourcePeak = max(sourcePeak, peak)
    sourceRootMeanSquare = max(sourceRootMeanSquare, rootMeanSquare)
    guard sourcePeak > 0 else { return 1 }
    var gain = purpose == .decoding ? Self.maximumDecodingGain : Self.maximumDetectionGain
    while gain > 1, exceedsHeadroom(gain: gain) { gain /= 2 }
    return gain
  }

  public mutating func reset() {
    sourcePeak = 0
    sourceRootMeanSquare = 0
  }

  private func exceedsHeadroom(gain: Float) -> Bool {
    sourcePeak * gain > Self.targetPeak
      || (purpose == .detection && sourceRootMeanSquare * gain > Self.detectionRootMeanSquare)
  }
}
