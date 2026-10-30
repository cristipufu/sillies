import Foundation

package struct ModelUpdateSnapshot: Codable, Equatable, Sendable {
  package struct Entry: Codable, Equatable, Sendable {
    package let installedRevision: String
    package let candidate: SpeechModelManifest?
    package let notice: String?
  }
  package var attemptedAt: Date?
  package var checkedAt: Date?
  package var entries: [String: Entry] = [:]
  package init() {}
}

/// Daily throttling survives restarts. Only installed models are queried.
package actor ModelUpdateChecker {
  package enum Check: Sendable { case scheduled, manual }
  package static let checkInterval: TimeInterval = 24 * 60 * 60
  private let store: ModelStore
  private let requestedLocation: URL
  private let discovery: any ModelUpdateDiscovering
  private let now: @Sendable () -> Date
  private var snapshot: ModelUpdateSnapshot?
  private var isChecking = false

  package init(
    store: ModelStore, location: URL,
    discovery: any ModelUpdateDiscovering = ModelUpdateDiscovery(),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.store = store
    self.requestedLocation = location
    self.discovery = discovery
    self.now = now
  }

  package func load() throws -> ModelUpdateSnapshot {
    if let snapshot { return snapshot }
    let location = try location()
    guard FileManager.default.fileExists(atPath: location.path) else {
      let empty = ModelUpdateSnapshot()
      snapshot = empty
      return empty
    }
    let data = try Data(contentsOf: location)
    let saved = try JSONDecoder().decode(ModelUpdateSnapshot.self, from: data)
    for entry in saved.entries.values { try entry.candidate?.validate() }
    snapshot = saved
    return saved
  }

  package func check(_ check: Check, models: [SpeechModelManifest]) async throws
    -> ModelUpdateSnapshot
  {
    var result = try load()
    guard !isChecking else { return result }
    let date = now()
    if check == .scheduled, let attempted = result.attemptedAt,
      date >= attempted, date.timeIntervalSince(attempted) < Self.checkInterval
    {
      return result
    }
    isChecking = true
    defer { isChecking = false }
    result.attemptedAt = date
    try save(result)
    var succeeded = true
    var installedIDs: Set<String> = []
    for baseline in models {
      try Task.checkCancellation()
      let installed = try await store.currentManifest(baseline)
      guard try await store.isInstalled(installed) else { continue }
      let id = installed.model.id
      installedIDs.insert(id)
      do {
        let candidate = try await discovery.candidate(for: installed)
        result.entries[id] = .init(
          installedRevision: installed.model.revision, candidate: candidate, notice: nil)
      } catch is CancellationError { throw CancellationError() } catch {
        succeeded = false
        ModelFiles.log(error)
        let previous = result.entries[id]
        let candidate =
          previous?.installedRevision == installed.model.revision ? previous?.candidate : nil
        result.entries[id] = .init(
          installedRevision: installed.model.revision, candidate: candidate,
          notice: error.localizedDescription)
      }
    }
    try Task.checkCancellation()
    result.entries = result.entries.filter { installedIDs.contains($0.key) }
    if succeeded { result.checkedAt = date }
    try save(result)
    return result
  }

  private func save(_ value: ModelUpdateSnapshot) throws {
    let location = try location()
    try ModelFiles.createDirectory(location.deletingLastPathComponent())
    try ModelFiles.write(value, to: location)
    snapshot = value
  }

  private func location() throws -> URL {
    let parent = requestedLocation.deletingLastPathComponent().resolvingSymlinksInPath()
    return try ModelFiles.child(requestedLocation.lastPathComponent, in: parent)
  }
}
