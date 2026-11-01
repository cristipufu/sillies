import Foundation
import MLXLMCommon
import SilliesTextModels

/// Checks the packaged native adapter and IPC without downloading or loading model weights.
enum TextConversationSelfCheck {
  static func run() throws {
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
            parameters: [.init("query", description: "Topic")])
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
    guard calls?.first?["id"] as? String == call.id,
      output["tool_call_id"] as? String == call.id, output["name"] as? String == call.name,
      MLXConversationInput.tools(request).count == 1
    else { throw TextModelError.invalidResponse }
    let measured = try JSONDecoder().decode(
      TextGenerationRequest.self,
      from: JSONEncoder().encode(request.measuringTokens()))
    guard measured.operation == .measure, measured.messages == request.messages else {
      throw TextModelError.invalidResponse
    }
  }
}
