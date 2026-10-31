import Foundation
import SilliesAudio
import SilliesSpeech
import SilliesWriting
import Synchronization
import Testing

private enum LateDestinationResult: CaseIterable, Sendable { case success, permission, unsupported }
private actor DelayedDestination: TextInserting {
  let staleID = UUID()
  private var count = 0
  private var continuation: CheckedContinuation<LateDestinationResult, Never>?
  var isWaiting: Bool { continuation != nil }
  var released: Set<UUID> = []
  var inserted: [String] = []
  func capture(_ application: FrontmostApplication) async throws -> TextDestination {
    count += 1
    if count == 1 {
      switch await withCheckedContinuation({ continuation = $0 }) {
      case .success: return .init(id: staleID, application: application, selection: "")
      case .permission: throw TextAccessError.permission
      case .unsupported: throw TextAccessError.unsupported
      }
    }
    return .init(id: UUID(), application: application, selection: "")
  }
  func resolve(_ result: LateDestinationResult) {
    continuation?.resume(returning: result)
    continuation = nil
  }
  func insert(_ text: String, into destination: TextDestination) { inserted.append(text) }
  func release(_ destination: TextDestination) { released.insert(destination.id) }
}

@Test(arguments: LateDestinationResult.allCases) @MainActor
private func dictationRestartRejectsLateDestinationSuccessAndFailure(
  _ outcome: LateDestinationResult
) async throws {
  let destination = DelayedDestination()
  let history = RecoveryHistory()
  let session = testDictation(insertion: destination, history: history)
  session.start(.toggle)
  for _ in 0..<200 {
    if await destination.isWaiting { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  try #require(await destination.isWaiting)
  session.cancel()
  session.start(.toggle)
  await destination.resolve(outcome)
  try await eventually { session.canFinish }
  session.finish()
  try await eventually { session.result != nil }
  #expect(session.insertionFailure == nil)
  #expect(session.result?.delivery == .inserted)
  #expect(await destination.inserted == ["Ștefan uses API_v2."])
  #expect(history.results.count == 1)
  if outcome == .success { #expect(await destination.released.contains(destination.staleID)) }
  session.dismiss()
}

private actor DelayedLanguages {
  private var count = 0
  private var continuation: CheckedContinuation<SpeechLanguageCatalog, any Error>?
  var isWaiting: Bool { continuation != nil }
  func load() async throws -> SpeechLanguageCatalog {
    count += 1
    if count == 1 { return try await withCheckedThrowingContinuation { continuation = $0 } }
    return Self.catalog
  }
  func resolve(_ outcome: Result<SpeechLanguageCatalog, any Error>) {
    continuation?.resume(with: outcome)
    continuation = nil
  }
  static var catalog: SpeechLanguageCatalog {
    .init(languages: [.init(id: "en-US", name: "English", isInstalled: true)])
  }
}

@Test(arguments: [true, false]) @MainActor
private func dictationRestartRejectsLateLanguageDiscovery(succeeds: Bool) async throws {
  let languages = DelayedLanguages()
  let starts = Mutex(0)
  let session = testDictation(
    insertion: WritingDestination(), history: RecoveryHistory(),
    configuration: .init(
      loadLanguages: { try await languages.load() },
      factory: { _, update in
        starts.withLock { $0 += 1 }
        return WritingCapture(update: update)
      }))
  session.start(.toggle)
  for _ in 0..<200 {
    if await languages.isWaiting { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  try #require(await languages.isWaiting)
  session.cancel()
  session.start(.toggle)
  await languages.resolve(
    succeeds ? .success(DelayedLanguages.catalog) : .failure(TextAccessError.failed))
  try await eventually { session.canFinish }
  session.finish()
  try await eventually { session.result != nil }
  #expect(starts.withLock { $0 } == 1)
  #expect(session.result?.delivery == .inserted)
  session.dismiss()
}

private actor DeferredCleanup {
  private var continuation: CheckedContinuation<String, Never>?
  var isWaiting: Bool { continuation != nil }
  func run() async -> String { await withCheckedContinuation { continuation = $0 } }
  func complete() {
    continuation?.resume(returning: "stale cleanup")
    continuation = nil
  }
}
@Test @MainActor func dictationRestartRejectsDelayedCleanupAndKeepsItsOwnSettings() async throws {
  let cleanup = DeferredCleanup()
  let preferences = WritingPreferences()
  preferences.style = .lightlyCleaned
  let destination = WritingDestination()
  let history = RecoveryHistory()
  let session = testDictation(
    insertion: destination, history: history,
    configuration: .init(preferences: preferences, transform: { _, _ in await cleanup.run() }))
  session.start(.toggle)
  try await eventually { session.canFinish }
  session.finish()
  for _ in 0..<200 {
    if await cleanup.isWaiting { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  try #require(await cleanup.isWaiting)
  session.cancel()
  preferences.style = .verbatim
  session.start(.toggle)
  try await eventually { session.canFinish }
  await cleanup.complete()
  session.finish()
  try await eventually { session.result != nil }
  #expect(await destination.inserted == ["Ștefan uses API_v2."])
  #expect(session.result?.text == "Ștefan uses API_v2.")
  #expect(history.results.allSatisfy { $0.text != "stale cleanup" })
  session.dismiss()
}
