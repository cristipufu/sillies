import CoreGraphics
import Foundation
import Vision

/// Swift Vision requests propagate task cancellation and keep decoding/inference off the UI actor.
enum WindowTextRecognition {
  @concurrent static func recognize(_ image: CGImage) async throws -> String {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    return try RecognizedDocumentText.render(await request().perform(on: image))
  }

  @concurrent static func recognize(_ url: URL) async throws -> String {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    return try RecognizedDocumentText.render(await request().perform(on: url))
  }

  private static func request() -> RecognizeDocumentsRequest {
    var request = RecognizeDocumentsRequest()
    request.textRecognitionOptions.automaticallyDetectLanguage = true
    request.textRecognitionOptions.useLanguageCorrection = true
    request.barcodeDetectionOptions.enabled = false
    return request
  }
}
