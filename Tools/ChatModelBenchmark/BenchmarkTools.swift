import Foundation
import SilliesCore
import SilliesReasoning

struct MeasuredConversationTool: ConversationTool {
  let base: any ConversationTool
  let events: BenchmarkEvents
  let position: BenchmarkPosition
  var definition: ConversationToolDefinition { base.definition }
  var activity: String { base.activity }
  func call(arguments: Data) async throws -> ConversationToolOutput {
    let start = ContinuousClock.now
    do {
      let output = try await base.call(arguments: arguments)
      try await record(arguments, result: output.text, error: nil, since: start)
      return output
    } catch {
      try await record(arguments, result: nil, error: String(describing: error), since: start)
      throw error
    }
  }
  private func record(
    _ arguments: Data, result: String?, error: String?, since start: ContinuousClock.Instant
  ) async throws {
    try await events.emit(
      .tool,
      BenchmarkToolResult(
        position: position, name: definition.name,
        arguments: String(decoding: arguments, as: UTF8.self),
        result: result, error: error, seconds: BenchmarkTurnTrace.seconds(start.duration(to: .now)))
    )
  }
}

/// Extra definitions measure distraction/schema pressure; they never gain access to real devices or data.
struct BenchmarkDistractorTool: ConversationTool {
  let definition: ConversationToolDefinition
  var activity: String { "Checking synthetic fixture data" }
  func call(arguments: Data) async throws -> ConversationToolOutput {
    struct Arguments: Decodable { let query: String }
    _ = try JSONDecoder().decode(Arguments.self, from: arguments)
    return .init(text: #"{"scope":"synthetic benchmark fixture","matches":[]}"#)
  }
  static let available: [Self] = [
    ("get_weather", "Look up weather forecasts for a city."),
    ("list_calendar_events", "Find upcoming calendar appointments by title."),
    ("search_contacts", "Find people and their contact details in the address book."),
    ("read_clipboard", "Read the current clipboard item."),
    ("search_music", "Find songs and albums in the local music library."),
    ("find_downloads", "Find files in the Downloads folder by filename."),
    ("read_system_status", "Look up battery, storage or CPU status."),
  ].map { name, description in
    .init(
      definition: .init(
        name: name, description: description,
        parameters: [
          .init("query", description: "Short keywords identifying the requested information.")
        ]))
  }
}
