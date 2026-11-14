import Foundation
import SilliesCore

package struct WindowSpeechModel: PreparedSpeechModel {
  private static let validationSamples = 16_000
  private let engine: any SpeechWindowEngine
  private let boundaryMode: SpeechBoundaryPolicy.Mode
  package init(engine: any SpeechWindowEngine, boundaryMode: SpeechBoundaryPolicy.Mode = .baseline)
  {
    self.engine = engine
    self.boundaryMode = boundaryMode
  }
  package func validate() async throws {
    // Bypass voice activity detection so the decoder actually runs on the candidate weights.
    let result = try await engine.transcribe(
      .init(samples: [Float](repeating: 0, count: Self.validationSamples), language: .automatic))
    guard result.words.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.end >= $0.start })
    else {
      throw SpeechError.unavailable(
        String(localized: "The updated speech model returned invalid timestamps."))
    }
  }
  package func makeChannel(_ request: SpeechChannelRequest) async throws -> any LocalSpeechChannel {
    try Task.checkCancellation()
    let recommended = request.context.purpose == .continuousTranscription ? boundaryMode : .baseline
    return try WindowSpeechChannel(engine: engine, request: request, boundaryMode: recommended)
  }
}
