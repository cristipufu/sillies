import FoundationModels
import SilliesTextModels

enum AppleConversationTranscript {
  static func make(_ request: TextGenerationRequest, tools: [Transcript.ToolDefinition] = []) throws
    -> Transcript
  {
    guard request.messages.last?.role == .user else { throw TextModelError.invalidResponse }
    var entries: [Transcript.Entry] = [
      .instructions(
        .init(segments: [.text(.init(content: request.instructions))], toolDefinitions: tools))
    ]
    for message in request.messages.dropLast() {
      let segments: [Transcript.Segment] = [.text(.init(content: message.content))]
      switch message.role {
      case .user: entries.append(.prompt(.init(segments: segments)))
      case .assistant:
        if !message.content.isEmpty {
          entries.append(.response(.init(assetIDs: [], segments: segments)))
        }
        if !message.calls.isEmpty {
          entries.append(
            .toolCalls(
              .init(
                try message.calls.map {
                  .init(
                    id: $0.id, toolName: $0.name,
                    arguments: try GeneratedContent(
                      json: String(decoding: $0.arguments, as: UTF8.self)))
                })))
        }
      case .tool:
        guard let id = message.callID, let name = message.toolName else {
          throw TextModelError.invalidResponse
        }
        entries.append(.toolOutput(.init(id: id, toolName: name, segments: segments)))
      }
    }
    return Transcript(entries: entries)
  }
}
