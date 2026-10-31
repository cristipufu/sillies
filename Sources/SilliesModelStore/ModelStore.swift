import Foundation

package actor ModelStore {
  private struct Receipt: Codable { let revision: String }
  private let requestedRoot: URL
  private lazy var root = requestedRoot.resolvingSymlinksInPath()
  private let downloader: any ModelDownloading
  private var installing: Set<String> = []
  private var leases: [String: Set<UUID>] = [:]
  private static let receiptName = "installed.json"

  package init(root: URL, downloader: any ModelDownloading = ModelDownloadClient()) {
    self.requestedRoot = root
    self.downloader = downloader
  }

  package func currentManifest(_ baseline: SpeechModelManifest) throws -> SpeechModelManifest {
    try ModelVersionSelection.read(for: baseline, root: root)?.current ?? baseline
  }

  package func previousManifest(_ baseline: SpeechModelManifest) throws -> SpeechModelManifest? {
    try ModelVersionSelection.read(for: baseline, root: root)?.previous
  }

  package func manifest(revision: String, baseline: SpeechModelManifest) throws
    -> SpeechModelManifest
  {
    let selection = try ModelVersionSelection.read(for: baseline, root: root)
    guard
      let match = [selection?.current, selection?.previous, baseline].compactMap({ $0 })
        .first(where: { $0.model.revision == revision })
    else { throw ModelStoreError.notInstalled }
    return match
  }

  package func activate(
    _ candidate: SpeechModelManifest, replacing baseline: SpeechModelManifest,
    validatedLease: InstalledModelLease, referenceLease: InstalledModelLease? = nil
  ) throws {
    try candidate.validate()
    let id = candidate.model.id
    guard id == baseline.model.id, candidate.model.providerID == baseline.model.providerID,
      candidate.model.purpose == baseline.model.purpose,
      validatedLease.directory == (try location(candidate)),
      leases[id]?.contains(validatedLease.token) == true
    else { throw ModelStoreError.invalidManifest }
    guard !installing.contains(id) else { throw ModelStoreError.busy }
    let previous = try currentManifest(baseline)
    if let referenceLease {
      guard referenceLease.directory == (try location(previous)),
        leases[id]?.contains(referenceLease.token) == true
      else { throw ModelStoreError.invalidManifest }
    }
    let validationTokens = Set([validatedLease.token, referenceLease?.token].compactMap { $0 })
    guard leases[id] == validationTokens else { throw ModelStoreError.inUse }
    guard previous != candidate else { return }
    try ModelVersionSelection(current: candidate, previous: previous).write(root: root)
  }

  package func isInstalled(_ manifest: any ModelArtifactManifest) throws -> Bool {
    try manifest.validate()
    let directory = try location(manifest)
    let receipt = try ModelFiles.child(Self.receiptName, in: directory)
    guard FileManager.default.fileExists(atPath: receipt.path) else { return false }
    let installed = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: receipt))
    guard installed.revision == manifest.revision else { return false }
    return try manifest.artifacts.allSatisfy { artifact in
      let file = try ModelFiles.child(artifact.path, in: directory)
      guard FileManager.default.fileExists(atPath: file.path) else { return false }
      let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      return values.isRegularFile == true && Int64(values.fileSize ?? -1) == artifact.byteCount
    }
  }

  package func stageUpdate(
    _ candidate: SpeechModelManifest, replacing baseline: SpeechModelManifest,
    progress: @escaping @Sendable (ModelInstallationProgress) -> Void
  ) async throws {
    try candidate.validate()
    guard candidate.model.id == baseline.model.id else { throw ModelStoreError.invalidManifest }
    guard leases[baseline.model.id, default: []].isEmpty else { throw ModelStoreError.inUse }
    guard !installing.contains(baseline.model.id) else { throw ModelStoreError.busy }
    let current = try currentManifest(baseline)
    guard try isInstalled(current) else { throw ModelStoreError.notInstalled }
    let previous = try previousManifest(baseline)
    try pruneVersions(
      for: baseline.model.id,
      keeping: [current.model.revision, previous?.model.revision, candidate.model.revision]
        .compactMap { $0 })
    try await install(candidate, progress: progress)
  }

  package func install(
    _ manifest: any ModelArtifactManifest,
    progress: @escaping @Sendable (ModelInstallationProgress) -> Void
  ) async throws {
    try manifest.validate()
    let id = manifest.modelID
    guard installing.insert(id).inserted else { throw ModelStoreError.busy }
    defer { installing.remove(id) }
    guard leases[id, default: []].isEmpty else { throw ModelStoreError.inUse }
    let destination = try location(manifest)
    let staging = try ModelFiles.child(id + ".partial", in: root)
    try ModelFiles.createDirectory(staging)
    try ModelFiles.checkCapacity(
      at: root, bytes: additionalDownloadBytes(manifest, staging: staging))
    var completed: Int64 = 0
    for artifact in manifest.artifacts {
      try Task.checkCancellation()
      let file = try ModelFiles.child(artifact.path, in: staging)
      let previous = completed
      try await installArtifact(artifact, at: file, staging: staging) { phase, bytes in
        progress(
          .init(
            phase: phase, completedBytes: previous + bytes,
            totalBytes: manifest.downloadBytes))
      }
      completed += artifact.byteCount
    }
    try Task.checkCancellation()
    try ModelFiles.write(
      Receipt(revision: manifest.revision),
      to: staging.appendingPathComponent(Self.receiptName))
    try ModelFiles.createDirectory(destination.deletingLastPathComponent())
    if FileManager.default.fileExists(atPath: destination.path) {
      _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
    } else {
      try FileManager.default.moveItem(at: staging, to: destination)
    }
  }

  package func acquire(_ manifest: any ModelArtifactManifest) throws -> InstalledModelLease {
    guard !installing.contains(manifest.modelID) else { throw ModelStoreError.busy }
    guard try isInstalled(manifest) else { throw ModelStoreError.notInstalled }
    let directory = try location(manifest)
    for artifact in manifest.artifacts {
      try ModelFiles.verify(artifact, at: ModelFiles.child(artifact.path, in: directory))
    }
    let token = UUID()
    let id = manifest.modelID
    leases[id, default: []].insert(token)
    return InstalledModelLease(directory: directory, token: token) { [weak self] in
      await self?.release(id, token: token)
    }
  }

  package func rollBack(_ baseline: SpeechModelManifest) throws {
    let id = baseline.model.id
    guard !installing.contains(id) else { throw ModelStoreError.busy }
    guard leases[id, default: []].isEmpty else { throw ModelStoreError.inUse }
    guard let selection = try ModelVersionSelection.read(for: baseline, root: root),
      let previous = selection.previous, try isInstalled(previous)
    else { throw ModelStoreError.notInstalled }
    for artifact in previous.artifacts {
      try ModelFiles.verify(artifact, at: ModelFiles.child(artifact.path, in: location(previous)))
    }
    try ModelVersionSelection(current: previous, previous: nil).write(root: root)
  }

  package func remove(_ manifest: any ModelArtifactManifest) throws {
    try manifest.validate()
    let id = manifest.modelID
    guard !installing.contains(id) else { throw ModelStoreError.busy }
    guard leases[id, default: []].isEmpty else { throw ModelStoreError.inUse }
    for path in [id, id + ".partial"] {
      let directory = try ModelFiles.child(path, in: root)
      if FileManager.default.fileExists(atPath: directory.path) {
        try FileManager.default.removeItem(at: directory)
      }
    }
  }

  private func release(_ id: String, token: UUID) { leases[id]?.remove(token) }

  private func pruneVersions(for id: String, keeping revisions: [String]) throws {
    let directory = try ModelFiles.child(id, in: root)
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    let children = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    for name in children where !revisions.contains(name) && name != "selection.json" {
      let child = try ModelFiles.child(name, in: directory)
      let receipt = try ModelFiles.child(Self.receiptName, in: child)
      if FileManager.default.fileExists(atPath: receipt.path) {
        try FileManager.default.removeItem(at: child)
      }
    }
  }

  private func additionalDownloadBytes(_ manifest: any ModelArtifactManifest, staging: URL) throws
    -> Int64
  {
    try manifest.artifacts.reduce(0) { remaining, artifact in
      let file = try ModelFiles.child(artifact.path, in: staging)
      guard FileManager.default.fileExists(atPath: file.path) else {
        return remaining + artifact.byteCount
      }
      let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      let reusable =
        values.isRegularFile == true ? min(Int64(values.fileSize ?? 0), artifact.byteCount) : 0
      return remaining + artifact.byteCount - reusable
    }
  }

  private func location(_ manifest: any ModelArtifactManifest) throws -> URL {
    try ModelFiles.child(manifest.modelID + "/" + manifest.revision, in: root)
  }

  private func installArtifact(
    _ artifact: ModelArtifact, at destination: URL, staging: URL,
    progress: @escaping @Sendable (ModelInstallationProgress.Phase, Int64) -> Void
  ) async throws {
    if FileManager.default.fileExists(atPath: destination.path) {
      do {
        progress(.verifying, artifact.byteCount)
        try ModelFiles.verify(artifact, at: destination)
        return
      } catch is CancellationError { throw CancellationError() } catch {
        ModelFiles.log(error)
        try FileManager.default.removeItem(at: destination)
      }
    }
    try ModelFiles.createDirectory(destination.deletingLastPathComponent())
    let resumeFile = staging.appendingPathComponent(artifact.sha256 + ".resume")
    progress(.downloading, 0)
    let temporary = try await downloader.download(
      .init(artifact: artifact, resumeFile: resumeFile, progress: { progress(.downloading, $0) }))
    defer {
      if FileManager.default.fileExists(atPath: temporary.path) {
        do { try FileManager.default.removeItem(at: temporary) } catch { ModelFiles.log(error) }
      }
    }
    progress(.verifying, artifact.byteCount)
    try ModelFiles.verify(artifact, at: temporary)
    try FileManager.default.moveItem(at: temporary, to: destination)
  }
}
