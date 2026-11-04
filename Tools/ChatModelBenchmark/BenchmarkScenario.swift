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
    var chatMessage: ChatMessage { .init(role: role == .user ? .user : .companion, text: text) }
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
  let history: [Message]
  /// Additional archived turns between measured requests, exercising checkpoint reuse.
  let historyBatches: [[Message]]?
  let records: [Record]
  let memories: [Fact]
  let turns: [String]
}
