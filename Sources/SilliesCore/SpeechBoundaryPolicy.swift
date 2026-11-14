import Foundation

/// Per-source acoustic decisions from supplied sample energy, independent of devices and clocks.
public struct SpeechBoundaryPolicy: Sendable {
  public enum Mode: String, Codable, CaseIterable, Sendable { case baseline, adaptive }
  public enum Activity: Sendable { case voice, quiet, invalid }
  public static let baselineThreshold: Float = 0.002
  public static let baselineSilence: TimeInterval = 0.6
  public static let maximumNoiseFrames = 200
  private static let speechLevelShare: Float = 0.2
  private static let minimumThreshold: Float = 0.0005
  private static let noiseMargin: Float = 1.8
  private static let calibrationSamples = 3_200
  public let mode: Mode
  private var quietEnergies: [Float] = []
  private var sourcePeak: Float = 0
  private var calibrationSamples = 0
  private var threshold = baselineThreshold
  var retainedNoiseFrames: Int { quietEnergies.count }
  public init(mode: Mode) { self.mode = mode }

  public mutating func observe(energy: Float, sampleCount: Int) -> Activity {
    guard energy.isFinite, energy >= 0, sampleCount > 0 else { return .invalid }
    if mode == .adaptive {
      sourcePeak = max(sourcePeak, energy)
      updateThreshold()
    }
    if energy > threshold {
      return .voice
    }
    if mode == .adaptive { learnQuietEnergy(energy, sampleCount: sampleCount) }
    return .quiet
  }
  private mutating func learnQuietEnergy(_ energy: Float, sampleCount: Int) {
    // Only quiet frames enter the noise estimate; the gate remains capped at its baseline.
    quietEnergies.append(energy)
    if quietEnergies.count > Self.maximumNoiseFrames { quietEnergies.removeFirst() }
    calibrationSamples = min(
      Self.calibrationSamples, calibrationSamples + min(Self.calibrationSamples, sampleCount))
    updateThreshold()
  }
  private mutating func updateThreshold() {
    guard calibrationSamples == Self.calibrationSamples else { return }
    let sorted = quietEnergies.sorted()
    let noiseFloor = sorted[sorted.count / 2] * Self.noiseMargin
    let speechFloor = sourcePeak * Self.speechLevelShare
    threshold = min(Self.baselineThreshold, max(Self.minimumThreshold, noiseFloor, speechFloor))
  }
  public mutating func reset() { self = Self(mode: mode) }

}
