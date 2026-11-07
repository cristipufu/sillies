import Foundation

/// External files are references. Vault cleanup must never unlink their targets.
public struct VaultFileReference: Identifiable, Equatable, Sendable {
  public static let maximumPerItem = 100
  public static let maximumPathScalars = 4_096
  public let id: UUID
  public let recordID: UUID
  public let originalPath: String
  public let path: String
  public var url: URL { URL(fileURLWithPath: path) }
  public init(id: UUID, recordID: UUID, originalPath: String, path: String) throws {
    guard Self.isValidPath(originalPath), Self.isValidPath(path) else {
      throw VaultEditingError.invalidValue
    }
    self.id = id
    self.recordID = recordID
    self.originalPath = originalPath
    self.path = path
  }
  public static func isValidPath(_ path: String) -> Bool {
    path.hasPrefix("/") && path.unicodeScalars.count <= maximumPathScalars && !path.contains("\0")
      && !path.contains("\n")
  }
}
