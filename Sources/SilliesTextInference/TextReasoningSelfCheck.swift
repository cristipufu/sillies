import Foundation
import MLXLMCommon
import SilliesTextModels

enum TextReasoningSelfCheck {
  private enum Failure: Error { case expectation(line: UInt) }
  static func run() throws {
    let gemma = ModelConfiguration(id: "fixture", toolCallFormat: .gemma4)
    let source = "<|channel>thought\nPrivate state<channel|>Visible answer"
    for offset in 0...source.count {
      let split = source.index(source.startIndex, offsetBy: offset)
      var channel = MLXReasoningChannel(configuration: gemma, promptTail: "")
      let text =
        channel.append(String(source[..<split]))
        + channel.append(String(source[split...])) + channel.finish()
      try require(text == "Visible answer" && channel.content == "Private state")
    }
    var primed = MLXReasoningChannel(configuration: gemma, promptTail: "<|channel>thought\n")
    try require(primed.append("unfinished private state") + primed.finish() == "")
    var plain = MLXReasoningChannel(configuration: ModelConfiguration(id: "plain"), promptTail: "")
    try require(plain.append("a < b, <think> is literal here") == "a < b, <think> is literal here")
    try checkThinkTags()
    try checkToolContinuation()
  }

  private static func checkThinkTags() throws {
    let model = ModelConfiguration(id: "fixture", reasoningConfig: .thinkTagsWithEnableThinking)
    let source = "<think>Private state</think>First<think>More private state</think>Second"
    for offset in 0...source.count {
      let split = source.index(source.startIndex, offsetBy: offset)
      var channel = MLXReasoningChannel(configuration: model, promptTail: "")
      let text =
        channel.append(String(source[..<split]))
        + channel.append(String(source[split...])) + channel.finish()
      try require(text == "FirstSecond" && channel.content == "Private stateMore private state")
    }
    var primed = MLXReasoningChannel(configuration: model, promptTail: "<think>\n")
    try require(primed.append("private</think>Visible") + primed.finish() == "Visible")
  }

  private static func checkToolContinuation() throws {
    let call = TextGenerationOutput.Call(id: "lookup", name: "search", arguments: Data("{}".utf8))
    let request = TextGenerationRequest(
      conversation: .init(
        instructions: "Answer",
        messages: [
          .init(role: .user, content: "Old question"),
          .calling([call], text: "", reasoningContent: "Old private state"),
          .result("Old result", for: call),
          .init(role: .user, content: "New question"),
          .calling([call], text: "", reasoningContent: "Current private state"),
          .result("New result", for: call),
        ], tools: []), maximumTokens: 240, style: .conversation)
    let native = try MLXConversationInput.templateMessages(request)
    try require(native[2]["reasoning_content"] == nil)
    try require(native[5]["reasoning_content"] as? String == "Current private state")
    try require(native[5]["content"] as? String == "")
    let noSystem = try MLXConversationInput.templateMessages(
      request, generator: NoSystemMessageGenerator())
    try require(noSystem.count == native.count - 1)
    try require(noSystem[4]["reasoning_content"] as? String == "Current private state")
    let encoded = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(TextGenerationRequest.self, from: encoded)
    try require(decoded.messages == request.messages)
    let response = TextInferenceResponse(
      output: .init(text: "", calls: [call], reasoningContent: "Current private state"))
    let transported = try JSONDecoder().decode(
      TextInferenceResponse.self, from: JSONEncoder().encode(response))
    try require(transported.reasoningContent == "Current private state")
    try require(transported.text == "")
  }

  private static func require(_ condition: Bool, line: UInt = #line) throws {
    guard condition else { throw Failure.expectation(line: line) }
  }
}
