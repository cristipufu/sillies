import Foundation
import SilliesCore
import SilliesTextModels

actor BenchmarkEvents {
  enum Kind: String, Encodable { case model, caseStarted, turnStarted, tool, turn, caseFinished }
  private struct Envelope<Payload: Encodable>: Encodable {
    let event: Kind
    let payload: Payload
  }
  func emit<Payload: Encodable & Sendable>(_ event: Kind, _ payload: Payload) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(Envelope(event: event, payload: payload))
    data.append(0x0A)
    try FileHandle.standardOutput.write(contentsOf: data)
  }
}

struct BenchmarkPosition: Codable, Sendable {
  let job: String
  let turn: Int
}

struct BenchmarkCaseResult: Codable, Sendable {
  let job: String
  let error: String?
  let completedTurns: Int
}

struct BenchmarkToolResult: Encodable, Sendable {
  let position: BenchmarkPosition
  let name: String
  let arguments: String
  let result: String?
  let error: String?
  let seconds: Double
}

struct BenchmarkTurnResult: Encodable, Sendable {
  struct TextEmission: Encodable, Sendable {
    let text: String
    let seconds: Double
  }
  struct Memory: Codable, Sendable {
    let key: String
    let value: String
    let source: String
  }
  let position: BenchmarkPosition
  let input: String
  let reply: String?
  let partialReply: String
  let error: String?
  let seconds: Double
  let firstTextSeconds: Double?
  let textEmissions: [TextEmission]
  let compactionCalls: Int
  let compactionSeconds: Double
  let requests: [TextGenerationRequest]
  let inputTokens: [Int]
  let generations: [BenchmarkGeneration]
  let compacted: Bool
  let summary: String
  let sources: [UUID]
  let memories: [Memory]
}

actor BenchmarkTurnTrace {
  struct Evidence: Sendable {
    let memories: [CompanionMemory]
    let generations: [BenchmarkGeneration]
    let progress: BenchmarkProgress.Snapshot
  }
  private let start = ContinuousClock.now
  private var firstText: Double?
  private var compacted = false
  private var compactionCalls = 0
  private var compactionSeconds = 0.0
  private var textEmissions: [BenchmarkTurnResult.TextEmission] = []
  private var requests: [TextGenerationRequest] = []
  private var inputTokens: [Int] = []
  private(set) var streamedText = ""

  func receivedText(_ text: String) {
    if firstText == nil, !text.isEmpty { firstText = elapsed }
    streamedText += text
    textEmissions.append(.init(text: text, seconds: elapsed))
  }
  func summarized(_ request: TextGenerationRequest) {
    compacted = true
    compactionCalls += 1
    requests.append(request)
  }
  func finishedSummary(seconds: Double) { compactionSeconds += seconds }
  func requested(_ request: TextGenerationRequest) { requests.append(request) }
  func counted(_ tokens: Int) { inputTokens.append(tokens) }
  var elapsed: Double { Self.seconds(start.duration(to: .now)) }
  static func seconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
  }

  func result(
    position: BenchmarkPosition, input: String, outcome: Result<ChatReply, any Error>,
    evidence: Evidence
  ) -> BenchmarkTurnResult {
    let reply = try? outcome.get()
    let memory = reply?.memory ?? evidence.progress.memory
    let sources = reply?.sources ?? evidence.progress.sources
    let failure: String?
    switch outcome {
    case .success: failure = nil
    case .failure(let error): failure = String(describing: error)
    }
    return .init(
      position: position, input: input, reply: reply?.text, partialReply: streamedText,
      error: failure,
      seconds: elapsed, firstTextSeconds: firstText,
      textEmissions: textEmissions, compactionCalls: compactionCalls,
      compactionSeconds: compactionSeconds, requests: requests,
      inputTokens: inputTokens, generations: evidence.generations,
      compacted: compacted, summary: memory?.summary ?? "",
      sources: sources.map(\.id),
      memories: evidence.memories.map {
        .init(key: $0.key, value: $0.value, source: $0.sourceQuote)
      })
  }
}
