import Foundation

/// Opt-in synthetic inspection spans. Native loading overlaps tokenizer and weight preparation.
struct TextPreparationTiming: Encodable, Sendable {
  enum Phase: String, Encodable, Sendable { case modelLoad, tokenizerSetup, inputPreparation }
  typealias Observer = @Sendable (Self) async -> Void
  let phase: Phase
  let seconds: Double

  init(_ phase: Phase, since start: ContinuousClock.Instant) {
    self.phase = phase
    let elapsed = start.duration(to: .now).components
    seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
  }
}
