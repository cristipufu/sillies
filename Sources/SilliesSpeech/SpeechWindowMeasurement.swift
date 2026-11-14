/// Content-free window decisions for explicitly injected local qualification observers.
package struct SpeechWindowMeasurement: Codable, Sendable {
  package let start: Double
  package let sampleCount: Int
  package let completion: SpeechWindowCompletion
  package init(start: Double, sampleCount: Int, completion: SpeechWindowCompletion) {
    self.start = start
    self.sampleCount = sampleCount
    self.completion = completion
  }
}
