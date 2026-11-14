/// Content-free work accounting for explicitly injected local qualification observers.
package struct SpeechInferenceMeasurement: Codable, Sendable {
  package let start: Double
  package let sampleCount: Int
  package let phase: SpeechWindowPosition.Phase
  package init(start: Double, sampleCount: Int, phase: SpeechWindowPosition.Phase) {
    self.start = start
    self.sampleCount = sampleCount
    self.phase = phase
  }
}
