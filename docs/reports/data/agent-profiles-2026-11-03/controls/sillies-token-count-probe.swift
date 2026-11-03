import Foundation
import FoundationModels

func duration(_ start: ContinuousClock.Instant) -> Double {
  let c = start.duration(to: .now).components
  return Double(c.seconds) + Double(c.attoseconds) / 1e18
}

func measure(_ label: String, _ operation: () async throws -> Int) async throws {
  let start = ContinuousClock.now
  let count = try await operation()
  print("\(label) tokens=\(count) seconds=\(duration(start))")
}

@main struct Probe {
  static func main() async throws {
    let text = "{\"status\":\"noResults\",\"coverage\":\"No matching saved records.\"}"
    for index in 0..<4 {
      try await measure("prompt-\(index)") {
        try await SystemLanguageModel.default.tokenCount(for: text)
      }
      try await measure("entries-\(index)") {
        try await SystemLanguageModel.default.tokenCount(for: [
          Transcript.Entry.instructions(.init(segments: [.text(.init(content: ""))], toolDefinitions: [])),
          .prompt(.init(segments: [.text(.init(content: text))]))
        ])
      }
    }
  }
}
