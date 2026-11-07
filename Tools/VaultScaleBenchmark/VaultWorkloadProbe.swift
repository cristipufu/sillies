import Foundation
import SilliesCore
import SilliesPersistence
import SilliesVault

extension VaultScaleBenchmark {
  static func concurrency(_ library: VaultLibrary) async throws {
    guard let header = try await library.workspacePage(.init()).records.first else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    let broad = Task {
      try await library.workspacePage(.init(text: "meeting", ordering: .relevance))
    }
    try await Task.sleep(for: .milliseconds(50))
    var detail: [Double] = []
    for _ in 0..<15 {
      let start = ContinuousClock.now
      _ = try await library.sectionPage(.init(recordID: header.id, section: .transcript))
      detail.append(milliseconds(start.duration(to: .now)))
    }
    let writeStart = ContinuousClock.now
    _ = try await library.editDocument(id: header.id, edit: .star, at: Date())
    let write = milliseconds(writeStart.duration(to: .now))
    let cancelStart = ContinuousClock.now
    broad.cancel()
    var cancelled = false
    do { _ = try await broad.value } catch is CancellationError { cancelled = true }
    let cancellation = milliseconds(cancelStart.duration(to: .now))
    let nextStart = ContinuousClock.now
    _ = try await library.workspacePage(.init())
    let subsequent = milliseconds(nextStart.duration(to: .now))
    if !header.metadata.isStarred {
      _ = try await library.editDocument(id: header.id, edit: .unstar, at: Date())
    }
    detail.sort()
    try emit(
      ConcurrencyResult(
        detailMedianMilliseconds: detail[detail.count / 2],
        detailP95Milliseconds: detail[Int(ceil(Double(detail.count) * 0.95)) - 1],
        saveMilliseconds: write, cancellationMilliseconds: cancellation,
        subsequentPageMilliseconds: subsequent, cancelled: cancelled))
  }

  static func longDocument(_ library: VaultLibrary) async throws {
    let text = String(
      repeating: "A long meeting keeps its original words, decisions and follow-ups. 🌳\n",
      count: 100_000)
    let record = SessionRecord(
      kind: .stash,
      origin: .init(
        characterID: "vault", characterName: "", source: .init(appName: "Scale fixture")))
    let started = ContinuousClock.now
    let header = try await library.createDocument(
      record: record,
      metadata: .init(kind: .note, title: "Synthetic long document", modifiedAt: Date()),
      notes: text)
    let creation = milliseconds(started.duration(to: .now))
    let location = VaultBlockLocation(recordID: header.id, section: .notes, ordinal: 1_000)
    let readStart = ContinuousClock.now
    let page = try await library.sectionPage(location)
    let read = milliseconds(readStart.duration(to: .now))
    let revision = try await library.sectionRevision(location)
    let editStart = ContinuousClock.now
    _ = try await library.editText(
      .init(
        location: location, expectedRevision: revision,
        text: "Corrected one page.\n",
        region: .blocks(location.ordinal..<(location.ordinal + page.blocks.count))), at: Date())
    let edit = milliseconds(editStart.duration(to: .now))
    try emit(
      LongDocumentResult(
        sourceBytes: text.utf8.count,
        creationMilliseconds: creation, pageMilliseconds: read, editMilliseconds: edit,
        loadedBlocks: page.blocks.count, loadedBodies: try await library.metrics().loadedBodies))
  }
}

private struct ConcurrencyResult: Encodable {
  let detailMedianMilliseconds: Double
  let detailP95Milliseconds: Double
  let saveMilliseconds: Double
  let cancellationMilliseconds: Double
  let subsequentPageMilliseconds: Double
  let cancelled: Bool
}
private struct LongDocumentResult: Encodable {
  let sourceBytes: Int
  let creationMilliseconds: Double
  let pageMilliseconds: Double
  let editMilliseconds: Double
  let loadedBlocks: Int
  let loadedBodies: Int
}
