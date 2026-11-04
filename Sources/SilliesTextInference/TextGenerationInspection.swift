import Foundation
import MLXLMCommon
import SilliesTextModels

/// Explicit synthetic replay: no tool execution; separate reasoning is omitted from the result.
/// Rejected tool frames are retained only here, never in normal inference responses or logging.
enum TextGenerationInspection {
  private static let maximumRequests = 8
  private struct Result: Encodable {
    let index: Int
    let seconds: Double
    let output: TextGenerationOutput?
    let failure: TextGenerationFailure?
    let error: String?
    let rejection: RejectedToolCall?
    let preparation: [TextPreparationTiming]
    let firstTextSeconds: Double?
  }

  private actor Timings {
    var preparation: [TextPreparationTiming] = []
    var firstTextSeconds: Double?
    var started = ContinuousClock.now
    func begin() {
      preparation = []
      firstTextSeconds = nil
      started = .now
    }
    func record(_ value: TextPreparationTiming) { preparation.append(value) }
    func receive(_ delta: String) {
      if firstTextSeconds == nil, !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        firstTextSeconds = TextGenerationInspection.seconds(since: started)
      }
    }
  }

  private actor Rejections {
    private var latest: RejectedToolCall?
    func record(_ value: RejectedToolCall) { latest = value }
    func take() -> RejectedToolCall? {
      defer { latest = nil }
      return latest
    }
  }

  static func run(requestURL: URL) async throws {
    let requests = try TextInferenceJSON.read(
      [TextInferenceRequest].self, from: requestURL,
      maximumBytes: TextInferenceWire.maximumMessageBytes)
    guard !requests.isEmpty, requests.count <= maximumRequests else {
      throw TextModelError.invalidResponse
    }
    let rejected = Rejections()
    let timings = Timings()
    let runtime = MLXTextRuntime(
      rejectionObserver: { await rejected.record($0) },
      timingObserver: { await timings.record($0) })
    for (index, request) in requests.enumerated() {
      let started = ContinuousClock.now
      await timings.begin()
      let result: Result
      do {
        let generated = try await runtime.generate(request, receive: { await timings.receive($0) })
        let visible = TextGenerationOutput(
          text: generated.text, calls: generated.calls, inputTokens: generated.inputTokens,
          metrics: generated.metrics)
        result = .init(
          index: index, seconds: seconds(since: started), output: visible, failure: nil,
          error: nil, rejection: await rejected.take(), preparation: await timings.preparation,
          firstTextSeconds: await timings.firstTextSeconds)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        result = .init(
          index: index, seconds: seconds(since: started), output: nil,
          failure: error as? TextGenerationFailure, error: String(describing: error),
          rejection: await rejected.take(), preparation: await timings.preparation,
          firstTextSeconds: await timings.firstTextSeconds)
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      try FileHandle.standardOutput.write(contentsOf: encoder.encode(result) + Data([10]))
    }
  }

  private static func seconds(since start: ContinuousClock.Instant) -> Double {
    let elapsed = start.duration(to: .now).components
    return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
  }
}
