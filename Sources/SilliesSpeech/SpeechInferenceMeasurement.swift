/// Content-free work accounting for explicitly injected local qualification observers.
package struct SpeechInferenceMeasurement: Sendable {
  package let sampleCount: Int
  package let phase: SpeechWindowPosition.Phase
  package init(sampleCount: Int, phase: SpeechWindowPosition.Phase) {
    self.sampleCount = sampleCount
    self.phase = phase
  }
}
