import Foundation

/// A portable note keeps its quotation even when the source is edited, trashed or removed.
public struct VaultSourceReference: Codable, Hashable, Sendable {
  public let location: VaultBlockLocation
  public let blockID: Int64
  public let revision: UUID

  public init(block: VaultContentBlock) {
    location = block.location
    blockID = block.id
    revision = block.revision
  }

  public var link: String {
    "sillies-vault://source/\(location.recordID.uuidString)/\(location.section.rawValue)/\(location.ordinal)?block=\(blockID)&revision=\(revision.uuidString)"
  }

  public init?(link: String) {
    guard let url = URLComponents(string: link), url.scheme == "sillies-vault",
      url.host == "source", url.user == nil, url.password == nil, url.port == nil,
      url.fragment == nil
    else { return nil }
    let path = url.path.split(separator: "/")
    guard path.count == 3, let id = UUID(uuidString: String(path[0])),
      let section = VaultDocumentSection(rawValue: String(path[1])),
      let ordinal = Int(path[2]), ordinal >= 0,
      let queries = url.queryItems, queries.count == 2,
      let block = queries.first(where: { $0.name == "block" })?.value.flatMap(Int64.init),
      block > 0,
      let revision = queries.first(where: { $0.name == "revision" })?.value.flatMap(
        UUID.init(uuidString:))
    else { return nil }
    location = .init(recordID: id, section: section, ordinal: ordinal)
    blockID = block
    self.revision = revision
  }
}
