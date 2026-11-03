import MLXLMCommon
import SilliesTextModels

/// The observed malformed frame stays rejected; only genuine native syntax may become a tool call.
enum TextRejectedToolSelfCheck {
  private enum Failure: Error { case expectation }
  private static let malformed =
    #"<|tool_call>call<audio|>_memories{query:<|"|>user_name<|"|>}<tool_call|>"#
  private static let valid =
    #"<|tool_call>call:search_memories{query:<|"|>user_name<|"|>}<tool_call|>"#

  static func run() throws {
    for chunks in partitions(of: malformed) {
      let events = process(chunks)
      guard events.count == 1, case .rejectedToolCall(let rejection) = events[0],
        rejection.reason == .malformedSyntax, rejection.rawTextPreview == malformed
      else { throw Failure.expectation }
      var collector = MLXGenerationCollector(
        style: .conversation,
        channel: .init(configuration: .init(id: "fixture", toolCallFormat: .gemma4), promptTail: "")
      )
      do {
        _ = try collector.consume(.rejectedToolCall(rejection))
        throw Failure.expectation
      } catch let failure as TextGenerationFailure {
        guard failure.reason == .rejectedToolCall,
          failure.outputCounts?.acceptedToolCalls == 0, failure.outputCounts?.responseBytes == 0
        else { throw failure }
      }
    }
    for chunks in partitions(of: valid) {
      let events = process(chunks)
      guard events.count == 1, case .toolCall(let call) = events[0],
        call.function.name == "search_memories",
        call.function.arguments["query"]?.anyValue as? String == "user_name"
      else { throw Failure.expectation }
    }
  }

  private static func process(_ chunks: [String]) -> [ToolCallProcessor.Output] {
    let processor = ToolCallProcessor(format: .gemma4)
    return chunks.flatMap { processor.processChunkOutputs($0) } + processor.processEOSOutputs()
  }

  private static func partitions(of source: String) -> [[String]] {
    (0...source.count).map { offset in
      let split = source.index(source.startIndex, offsetBy: offset)
      return [String(source[..<split]), String(source[split...])]
    } + [source.map(String.init)]
  }
}
