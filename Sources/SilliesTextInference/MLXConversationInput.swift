import Foundation
import MLXLMCommon
import SilliesTextModels

enum MLXConversationInput {
  static func templateMessages(
    _ request: TextGenerationRequest, generator: any MessageGenerator = DefaultMessageGenerator()
  ) throws -> [[String: any Sendable]] {
    var native = try generator.generate(messages: messages(request))
    guard let lastUser = request.messages.lastIndex(where: { $0.role == .user }) else {
      return native
    }
    for message in request.messages.dropFirst(lastUser + 1) {
      guard message.role == .assistant, !message.calls.isEmpty,
        let reasoning = message.reasoningContent
      else { continue }
      guard
        let index = native.lastIndex(where: { value in
          let calls = value["tool_calls"] as? [[String: any Sendable]]
          return calls?.compactMap { $0["id"] as? String } == message.calls.map(\.id)
        })
      else { throw TextModelError.invalidResponse }
      // Only an unfinished tool turn retains private state. Ordinary history never does.
      native[index]["reasoning_content"] = reasoning
    }
    return native
  }

  static func messages(_ request: TextGenerationRequest) throws -> [Chat.Message] {
    try [.system(request.instructions)] + messages(request.messages)
  }

  static func messages(_ messages: [TextMessage]) throws -> [Chat.Message] {
    try messages.map { message in
      switch message.role {
      case .user: return .user(message.content)
      case .assistant:
        let calls = try message.calls.map {
          ToolCall(
            function: .init(
              name: $0.name,
              arguments: try JSONDecoder().decode([String: JSONValue].self, from: $0.arguments)),
            id: $0.id)
        }
        return .assistant(message.content, toolCalls: calls.isEmpty ? nil : calls)
      case .tool: return .tool(message.content, id: message.callID, name: message.toolName)
      }
    }
  }

  static func tools(_ request: TextGenerationRequest) -> [[String: any Sendable]] {
    request.tools.map { tool in
      var properties: [String: any Sendable] = [:]
      for parameter in tool.parameters {
        var property: [String: any Sendable] = ["description": parameter.description]
        switch parameter.kind {
        case .string: property["type"] = "string"
        case .integer: property["type"] = "integer"
        case .boolean: property["type"] = "boolean"
        case .choice(let choices):
          property["type"] = "string"
          property["enum"] = choices
        }
        properties[parameter.name] = property
      }
      return [
        "type": "function",
        "function": [
          "name": tool.name, "description": tool.description,
          "parameters": [
            "type": "object", "properties": properties,
            "required": tool.parameters.map(\.name), "additionalProperties": false,
          ] as [String: any Sendable],
        ] as [String: any Sendable],
      ]
    }
  }
}
