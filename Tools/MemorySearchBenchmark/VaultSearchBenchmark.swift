import Foundation
import SilliesCore
import SilliesInference
import SilliesSearchModels
import SilliesVault

enum VaultSearchBenchmark {
  static func run(_ input: Input, arguments: [String]) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sillies-vault-probe-\(UUID())")
    let library = VaultLibrary(directory: directory)
    let records = input.documents.map { document in
      SessionRecord(
        kind: .record,
        origin: .init(
          characterID: "fixture", characterName: "Fixture",
          source: .init(appName: "Synthetic", windowTitle: document.id)),
        content: .init(text: .init(transcript: document.text)))
    }
    _ = try await library.commit(.init(records: records.map { .insert($0) }))
    let session = EmbeddingWorkerSession(
      configuration: .init(
        provider: arguments[3], identity: arguments[4],
        directory: arguments.count == 6 ? URL(fileURLWithPath: arguments[5]) : nil),
      executable: URL(fileURLWithPath: arguments[2]), modelBytes: 512 * 1024 * 1024,
      activity: InferenceActivity())
    do {
      if arguments[3] != "keywords" {
        try await library.useSearchEmbeddings(session.access())
        try await waitForIndex(library)
      }
      for query in input.queries {
        let started = ContinuousClock.now
        let matches = try await library.search(.init(query: query.text))
        let duration = started.duration(to: .now).components
        let result = Result(
          id: query.id, matches: matches.compactMap(\.header.windowTitle),
          seconds: Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
        try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(result) + Data([10]))
      }
    } catch {
      await session.stop()
      try await library.useSearchEmbeddings(nil)
      try FileManager.default.removeItem(at: directory)
      throw error
    }
    await session.stop()
    try await library.useSearchEmbeddings(nil)
    try FileManager.default.removeItem(at: directory)
  }

  private static func waitForIndex(_ library: VaultLibrary) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(45))
    while ContinuousClock.now < deadline {
      let (progress, failure) = try await library.searchIndexStatus()
      if failure != nil { throw ProbeError.indexFailed }
      if let progress, progress.processed == progress.total { return }
      try await Task.sleep(for: .milliseconds(20))
    }
    throw ProbeError.indexFailed
  }
}
