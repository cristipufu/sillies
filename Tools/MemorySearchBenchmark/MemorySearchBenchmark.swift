import Foundation
import SilliesCore
import SilliesInference
import SilliesSearchModels
import SilliesVault

/// Headless, synthetic-only production-path probe. Relevance labels are scored by a separate process.
@main enum MemorySearchBenchmark {
  static func main() async throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 5 || arguments.count == 6 else {
      throw ProbeError.usage
    }
    let input = try JSONDecoder().decode(
      Input.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
    guard input.documents.count <= 1000, input.queries.count <= 1000 else { throw ProbeError.usage }
    if input.scope == "vault" {
      try await VaultSearchBenchmark.run(input, arguments: arguments)
      return
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sillies-search-probe-\(UUID())")
    let library = ConversationLibrary(directory: directory)
    var handles: [String: ConversationHandle] = [:]
    for document in input.documents {
      let snapshot = try await library.open(.init(id: document.owner, name: document.owner))
      handles[document.owner] = snapshot.handle
      let source = ChatMessage(role: .user, text: document.text)
      try await library.save(
        .init(
          handle: snapshot.handle, messages: [source], checkpoint: .init(), savedAt: .distantPast))
      _ = try await library.remember(
        .init(
          handle: snapshot.handle,
          fact: .init(key: document.id, value: document.text),
          source: .init(messageID: source.id, quote: source.text), savedAt: .distantPast))
    }
    var session: EmbeddingWorkerSession?
    do {
      if arguments[3] != "keywords" {
        let modelDirectory = arguments.count == 6 ? URL(fileURLWithPath: arguments[5]) : nil
        let runtime = EmbeddingWorkerSession(
          configuration: .init(
            provider: arguments[3], identity: arguments[4], directory: modelDirectory),
          executable: URL(fileURLWithPath: arguments[2]), modelBytes: 512 * 1024 * 1024,
          activity: InferenceActivity())
        session = runtime
        try await library.useSearchEmbeddings(runtime.access())
        try await waitForIndex(library)
      }
      for query in input.queries {
        guard let handle = handles[query.owner] else { throw ProbeError.usage }
        let started = ContinuousClock.now
        let matches = try await library.memories(.init(handle: handle, text: query.text))
        let duration = started.duration(to: .now).components
        let result = Result(
          id: query.id, matches: matches.map(\.key),
          seconds: Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
        try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(result) + Data([10]))
      }
    } catch {
      await session?.stop()
      try await library.useSearchEmbeddings(nil)
      try FileManager.default.removeItem(at: directory)
      throw error
    }
    await session?.stop()
    try await library.useSearchEmbeddings(nil)
    try FileManager.default.removeItem(at: directory)
  }

  private static func waitForIndex(_ library: ConversationLibrary) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(45))
    while ContinuousClock.now < deadline {
      let (progress, failure) = try await library.memoryIndexStatus()
      if failure != nil { throw ProbeError.indexFailed }
      if let progress, progress.processed == progress.total { return }
      try await Task.sleep(for: .milliseconds(20))
    }
    throw ProbeError.indexFailed
  }
}

struct Input: Decodable {
  let scope: String?
  struct Text: Decodable {
    let id: String
    let owner: String
    let text: String
  }
  let documents: [Text]
  let queries: [Text]
}
struct Result: Encodable {
  let id: String
  let matches: [String]
  let seconds: Double
}
enum ProbeError: Error { case usage, indexFailed }
