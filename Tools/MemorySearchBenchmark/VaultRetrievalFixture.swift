import Foundation
import SilliesCore

/// Gold labels live in the independent scorer, never in the retrieval process.
struct VaultRetrievalFixture: Decodable {
  struct Document: Decodable {
    let id: UUID
    let title: String
    let text: String
    let tag: String?
    let trashed: Bool?
  }
  struct Query: Decodable {
    let id: String
    let text: String
    let tag: String?
    let scope: VaultWorkspaceQuery.Scope?
    var workspace: VaultWorkspaceQuery {
      var query = VaultWorkspaceQuery(scope: scope ?? .all, text: text, ordering: .relevance)
      query.tag = tag
      return query
    }
  }
  let documents: [Document]
  let queries: [Query]

  static func load(_ url: URL) throws -> Self {
    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
    guard bytes <= 64 * 1_024 * 1_024 else { throw ProbeError.usage }
    let fixture = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    guard !fixture.documents.isEmpty, fixture.documents.count <= 20_000,
      !fixture.queries.isEmpty, fixture.queries.count <= 1_000,
      Set(fixture.documents.map(\.id)).count == fixture.documents.count,
      Set(fixture.queries.map(\.id)).count == fixture.queries.count
    else { throw ProbeError.usage }
    return fixture
  }
}

struct VaultRetrievalRun {
  let mode: String
  let fixtureURL: URL
  let directory: URL
  let helper: URL
  let provider: String
  let identity: String
  let modelDirectory: URL?
  static let sliceDuration: Duration = .seconds(20)

  init(_ arguments: [String]) throws {
    guard (6...7).contains(arguments.count), ["seed", "index", "query"].contains(arguments[0]),
      ["keywords", "apple", "e5"].contains(arguments[4])
    else { throw ProbeError.usage }
    mode = arguments[0]
    fixtureURL = URL(fileURLWithPath: arguments[1])
    directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
    helper = URL(fileURLWithPath: arguments[3])
    provider = arguments[4]
    identity = arguments[5]
    modelDirectory = arguments.count == 7 ? URL(fileURLWithPath: arguments[6]) : nil
  }

  func validateOwnership() throws {
    let files = FileManager.default
    let marker = directory.appendingPathComponent("qualification-input.json")
    let input = try Data(contentsOf: fixtureURL)
    if files.fileExists(atPath: marker.path) {
      guard try Data(contentsOf: marker) == input else { throw ProbeError.usage }
    } else {
      guard mode == "seed", !files.fileExists(atPath: directory.path) else {
        throw ProbeError.usage
      }
      try files.createDirectory(at: directory, withIntermediateDirectories: true)
      try input.write(to: marker, options: .atomic)
    }
  }
}
