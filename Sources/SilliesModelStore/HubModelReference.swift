import Foundation

/// Only repositories already named in an installed manifest can supply updates.
struct HubModelReference: Hashable, Sendable {
  let repository: String
  let revision: String
  let path: String

  init(_ url: URL) throws {
    var parts = url.pathComponents.dropFirst().makeIterator()
    guard url.scheme == "https", url.host == "huggingface.co",
      let owner = parts.next(), let name = parts.next(), parts.next() == "resolve",
      let revision = parts.next(), Self.isRevision(revision),
      ModelFiles.isSafeComponent(owner), ModelFiles.isSafeComponent(name)
    else { throw ModelStoreError.invalidManifest }
    repository = owner + "/" + name
    self.revision = revision
    path = Array(parts).joined(separator: "/")
    guard ModelFiles.isSafeRelativePath(path) else { throw ModelStoreError.invalidManifest }
  }

  func url(at revision: String, path: String? = nil) throws -> URL {
    guard Self.isRevision(revision),
      let url = URL(
        string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(path ?? self.path)")
    else { throw ModelStoreError.invalidManifest }
    return url
  }

  static func isRevision(_ value: String) -> Bool {
    value.count == 40 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}
