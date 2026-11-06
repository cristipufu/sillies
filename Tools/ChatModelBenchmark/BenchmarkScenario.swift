import Foundation
import SilliesCore

/// Only model-visible scenario inputs cross the worker boundary; the evaluator retains the gold data.
struct BenchmarkPlan: Decodable, Sendable {
  let model: String
  let modelDirectory: String
  let helper: String
  let workspace: String
  let jobs: [BenchmarkJob]
  let memorySearch: BenchmarkMemorySearch.Configuration?
  let prefillChunkTokens: Int?
}

struct BenchmarkJob: Codable, Sendable {
  let id: String
  let scenario: BenchmarkScenario
  let tools: BenchmarkToolProfile
}

struct BenchmarkScenario: Codable, Sendable {
  struct Owner: Codable, Sendable {
    let id: String
    let name: String
    let personality: String
  }
  struct Message: Codable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    let role: Role
    let text: String
    let spokenText: String?
    let interrupted: Bool?
    var chatMessage: ChatMessage {
      let message = ChatMessage(role: role == .user ? .user : .companion, text: text)
      guard interrupted == true else { return message }
      return message.withDelivery(.interrupted, spokenText: spokenText)
    }
  }
  struct Record: Codable, Sendable {
    let id: UUID
    let kind: CompanionSkillKind
    let app: String
    let title: String
    let text: String
    let links: [String]
  }
  struct Fact: Codable, Sendable {
    let key: String
    let value: String
    let statement: String
  }
  let id: String
  let owner: Owner
  let language: String
  let mode: String?
  let history: [Message]
  /// Additional archived turns between measured requests, exercising checkpoint reuse.
  let historyBatches: [[Message]]?
  let records: [Record]
  let memories: [Fact]
  let turns: [String]
}
