import Foundation
import FoundationModels

func seconds(_ start: ContinuousClock.Instant) -> Double {
  let d = start.duration(to: .now).components
  return Double(d.seconds) + Double(d.attoseconds) / 1e18
}
enum Mode: String { case plain, counted }
struct Lookup: Tool {
  let name = "lookup"
  let description = "Find the user's assigned project code."
  let mode: Mode
  @Generable struct Arguments { var query: String }
  func call(arguments: Arguments) async throws -> String {
    let result = "{\"code\":\"quartz-73\"}"
    if mode == .counted {
      let start = ContinuousClock.now
      let n = try await SystemLanguageModel.default.tokenCount(for: [
        Transcript.Entry.instructions(.init(segments: [.text(.init(content: ""))], toolDefinitions: [])),
        .prompt(.init(segments: [.text(.init(content: result))]))
      ])
      print("count seconds=\(seconds(start)) tokens=\(n)")
    }
    return result
  }
}
@main struct Probe {
  static func main() async throws {
    for mode in [Mode.plain, .counted, .counted, .plain, .plain, .counted] {
      let session = LanguageModelSession(tools: [Lookup(mode: mode)], instructions: "Use lookup to answer the user's private question. Reply with the code only.")
      let start = ContinuousClock.now
      var first: Double?
      var text = ""
      for try await item in session.streamResponse(to: "What is my assigned project code?", options: .init(samplingMode: .greedy, maximumResponseTokens: 100)) {
        if !item.content.isEmpty && first == nil { first = seconds(start) }
        text = item.content
      }
      print("mode=\(mode.rawValue) first=\(first ?? -1) total=\(seconds(start)) reply=\(text)")
    }
  }
}
