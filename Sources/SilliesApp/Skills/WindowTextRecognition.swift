import CoreGraphics
import Foundation
import Vision

/// Swift Vision requests propagate task cancellation and keep decoding/inference off the UI actor.
enum WindowTextRecognition {
  @concurrent static func recognize(_ image: CGImage) async throws -> String {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    return try render(await request().perform(on: image))
  }

  @concurrent static func recognize(_ url: URL) async throws -> String {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    return try render(await request().perform(on: url))
  }

  private static func request() -> RecognizeTextRequest {
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.automaticallyDetectsLanguage = true
    request.usesLanguageCorrection = true
    return request
  }

  private static func render(_ observations: [RecognizedTextObservation]) throws -> String {
    try Task.checkCancellation()
    return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
  }
}
