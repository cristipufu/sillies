import Foundation
import MLXLMCommon
import SilliesTextModels

/// Checks the packaged native adapter and IPC without downloading or loading model weights.
enum TextConversationSelfCheck {
  static func run() throws {
    try checkWithdrawnToolSchema()
    let call = TextGenerationOutput.Call(
      id: "lookup", name: "search_vault",
      arguments: Data(#"{"query":"Ghostty"}"#.utf8))
    let request = TextGenerationRequest(
      conversation: .init(
        instructions: "Use local sources.",
        messages: [
          .init(role: .user, content: "Find Ghostty"), .calling([call], text: ""),
          .result("Saved screenshot", for: call), .init(role: .user, content: "Read it"),
        ],
        tools: [
          .init(
            name: call.name, description: "Search saved records",
            parameters: [
              .init("query", description: "Topic"),
              .init("offset", description: "Continuation", kind: .integer, requirement: .optional),
            ])
        ]),
      maximumTokens: 240, style: .conversation)
    let native = try MLXConversationInput.messages(request)
    guard native.map(\.role) == [.system, .user, .assistant, .tool, .user],
      let assistant = native.first(where: { $0.role == .assistant }),
      let result = native.first(where: { $0.role == .tool })
    else { throw TextModelError.invalidResponse }
    let generator = DefaultMessageGenerator()
    let calls = generator.generate(message: assistant)["tool_calls"] as? [[String: any Sendable]]
    let output = generator.generate(message: result)
    let definition =
      MLXConversationInput.tools(request).first?["function"] as? [String: any Sendable]
    let schema = definition?["parameters"] as? [String: any Sendable]
    let properties = schema?["properties"] as? [String: any Sendable]
    guard calls?.first?["id"] as? String == call.id,
      output["tool_call_id"] as? String == call.id, output["name"] as? String == call.name,
      schema?["required"] as? [String] == ["query"], properties?["offset"] != nil
    else { throw TextModelError.invalidResponse }
    let measured = try JSONDecoder().decode(
      TextGenerationRequest.self,
      from: JSONEncoder().encode(request.measuringTokens()))
    guard measured.operation == .measure, measured.messages == request.messages else {
      throw TextModelError.invalidResponse
    }
  }

  private static func checkWithdrawnToolSchema() throws {
    let request = TextGenerationRequest(
      instructions: "The tool budget is exhausted. Answer from returned evidence.",
      prompt: "Which links did I save?", maximumTokens: 240, style: .conversation)
    let processor = ToolCallProcessor(
      format: .gemma4, tools: MLXConversationInput.nativeTools(request))
    let source =
      #"<|tool_call>call:read_vault_record{recordID:<|"|>fixture<|"|>,query:<|"|>links<|"|>}<tool_call|>"#
    let events = processor.processChunkOutputs(source) + processor.processEOSOutputs()
    guard events.count == 1, case .toolCall(let call) = events[0],
      call.function.name == "read_vault_record"
    else { throw TextModelError.invalidResponse }
    // Parsing is not execution: ConversationToolbox's quota tests ensure this late call can
    // receive the existing budget response but cannot perform another operation.
  }
}
