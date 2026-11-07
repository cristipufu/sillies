import Foundation
import SilliesCore
import SilliesInference
import SilliesSearchModels
import SilliesVault

/// Each invocation makes bounded progress on its disposable archive and can resume after process exit.
enum VaultRetrievalBenchmark {
  static func run(_ arguments: [String]) async throws {
    let run = try VaultRetrievalRun(arguments)
    let fixture = try VaultRetrievalFixture.load(run.fixtureURL)
    try run.validateOwnership()
    let library = VaultLibrary(directory: run.directory, cacheBytes: 0)
    _ = try await library.snapshot()
    if run.mode == "seed" {
      try await seed(fixture, library: library)
      return
    }
    let session = EmbeddingWorkerSession(
      configuration: .init(
        provider: run.provider, identity: run.identity, directory: run.modelDirectory),
      executable: run.helper, modelBytes: 512 * 1_024 * 1_024, activity: InferenceActivity())
    do {
      let access = run.provider == "keywords" ? nil : try await session.access()
      if let access { try await library.useSearchEmbeddings(access) }
      if run.mode == "index" {
        try await index(library)
      } else {
        try await evaluate(fixture, run: run, library: library, access: access)
      }
      try await library.useSearchEmbeddings(nil)
      await session.stop()
    } catch {
      do { try await library.useSearchEmbeddings(nil) } catch {
        fputs("Qualification index shutdown failed: \(error)\n", stderr)
      }
      await session.stop()
      throw error
    }
  }

  private static func evaluate(
    _ fixture: VaultRetrievalFixture, run: VaultRetrievalRun, library: VaultLibrary,
    access: SearchEmbeddingAccess?
  ) async throws {
    let oracle: VaultRetrievalOracle?
    if let access {
      oracle = try await VaultRetrievalOracle.make(directory: run.directory, access: access)
    } else {
      oracle = nil
    }
    do {
      try await VaultRetrievalQueries.evaluate(fixture, run: run, library: library, oracle: oracle)
      try await oracle?.stop()
    } catch {
      do { try await oracle?.stop() } catch {
        fputs("Exact retrieval shutdown failed: \(error)\n", stderr)
      }
      throw error
    }
  }

  private static func seed(_ fixture: VaultRetrievalFixture, library: VaultLibrary) async throws {
    let deadline = ContinuousClock.now.advanced(by: VaultRetrievalRun.sliceDuration)
    var prepared = 0
    for document in fixture.documents {
      if try await library.documentHeader(id: document.id) == nil {
        let record = SessionRecord(
          kind: .stash,
          origin: .init(
            characterID: "fixture", characterName: "Fixture",
            source: .init(appName: "Qualification")),
          metadata: .init(id: document.id, createdAt: .distantPast))
        var metadata = VaultDocumentMetadata(
          kind: .note, title: document.title, modifiedAt: .distantPast)
        metadata.tags = document.tag.map { [$0] } ?? []
        if document.trashed == true { metadata.trashedAt = .distantPast }
        _ = try await library.createDocument(
          record: record, metadata: metadata, notes: document.text)
      }
      prepared += 1
      if ContinuousClock.now >= deadline { break }
    }
    try emit(
      Progress(
        stage: "seed", processed: prepared, total: fixture.documents.count,
        complete: prepared == fixture.documents.count))
  }

  private static func index(_ library: VaultLibrary) async throws {
    let deadline = ContinuousClock.now.advanced(by: VaultRetrievalRun.sliceDuration)
    while true {
      let (progress, failure) = try await library.searchIndexStatus()
      if let failure { throw QualificationFailure(message: failure) }
      guard let progress else { throw ProbeError.indexFailed }
      let preparing = await library.isPreparingSearch
      let complete = progress.processed == progress.total && !preparing
      if complete || ContinuousClock.now >= deadline {
        try emit(
          Progress(
            stage: "index", processed: progress.processed, total: progress.total, complete: complete
          ))
        return
      }
      try await Task.sleep(for: .milliseconds(50))
    }
  }

  static func emit(_ value: some Encodable) throws {
    try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(value) + Data([10]))
  }
  struct Progress: Encodable {
    let stage: String
    let processed: Int
    let total: Int
    let complete: Bool
  }
  struct QualificationFailure: Error { let message: String }
}
