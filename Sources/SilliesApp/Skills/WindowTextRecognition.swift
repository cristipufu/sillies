import CoreGraphics
import Foundation
import Vision

enum WindowTextRecognition {
  static func recognize(_ image: CGImage) async throws -> String {
    try await Task.detached(priority: .utility) {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
      return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(
        separator: "\n")
    }.value
  }
}
