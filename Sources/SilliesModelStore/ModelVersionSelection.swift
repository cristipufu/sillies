import Foundation

/// The pointer changes atomically only after a complete candidate passes runtime validation.
struct ModelVersionSelection: Codable {
  let current: SpeechModelManifest
  let previous: SpeechModelManifest?

  static func read(for baseline: SpeechModelManifest, root: URL) throws -> Self? {
    let url = try location(baseline.model.id, root: root)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let selection = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    for manifest in [selection.current, selection.previous].compactMap({ $0 }) {
      try manifest.validate()
      guard manifest.model.id == baseline.model.id,
        manifest.model.providerID == baseline.model.providerID,
        manifest.model.purpose == baseline.model.purpose
      else { throw ModelStoreError.invalidManifest }
    }
    return selection
  }

  func write(root: URL) throws {
    let url = try Self.location(current.model.id, root: root)
    try ModelFiles.createDirectory(url.deletingLastPathComponent())
    try ModelFiles.write(self, to: url)
  }

  private static func location(_ id: String, root: URL) throws -> URL {
    try ModelFiles.child(id + "/selection.json", in: root)
  }
}
