import Foundation

/// A reference supplied by a local tool, never a link invented by a model.
public struct ChatSource: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let title: String
  public let kind: CompanionSkillKind
  public let createdAt: Date
  public private(set) var excerpt: String
  public let links: [URL]
  public let imageFilename: String?
  private var savedPassages: [VaultEvidencePassage]?
  private var recordingAvailable: Bool?
  public var hasRecording: Bool { recordingAvailable == true }
  public var passages: [VaultEvidencePassage] { savedPassages ?? [] }
  public func withPassages(_ passages: [VaultEvidencePassage]) -> Self {
    var copy = self
    let admitted = Array(
      passages.filter {
        $0.reference.location.recordID == id
      }.prefix(VaultEvidencePassage.maximumPerSource))
    copy.savedPassages = admitted.isEmpty ? nil : admitted
    return copy
  }
  public func mergingEvidence(from source: Self) -> Self {
    guard id == source.id else { return self }
    guard !source.passages.isEmpty || !passages.isEmpty else { return source }
    var merged = passages
    for passage in source.passages where !merged.contains(where: { $0.contains(passage) }) {
      let position = merged.firstIndex { passage.contains($0) } ?? merged.count
      merged.removeAll { passage.contains($0) }
      guard merged.count < VaultEvidencePassage.maximumPerSource else { break }
      merged.insert(passage, at: min(position, merged.count))
    }
    return withPassages(merged)
  }
  public func withExcerpt(_ text: String) -> Self {
    var copy = self
    copy.excerpt = text
    if text != excerpt {
      var cursor = excerpt.startIndex
      let end = excerpt.index(excerpt.startIndex, offsetBy: min(text.count, excerpt.count))
      let admitted: [VaultEvidencePassage] =
        excerpt.hasPrefix(text)
        ? passages.compactMap { passage in
          guard let range = excerpt.range(of: passage.text, range: cursor..<excerpt.endIndex) else {
            return nil
          }
          cursor = range.upperBound
          guard range.lowerBound < end else { return nil }
          return passage.prefix(
            excerpt.distance(from: range.lowerBound, to: min(end, range.upperBound)))
        } : []
      copy.savedPassages = admitted.isEmpty ? nil : admitted
    }
    return copy
  }
  private let retrievalMethod: VaultSearchMatch.Retrieval?
  public var retrieval: VaultSearchMatch.Retrieval { retrievalMethod ?? .keyword }
  public var audioFilename: String? { nil }

  public init(
    header: SessionRecordHeader, excerpt: String, links: [URL] = [],
    retrieval: VaultSearchMatch.Retrieval = .keyword
  ) {
    self.init(.init(header: header, excerpt: excerpt, retrieval: retrieval), links: links)
  }

  public init(_ match: VaultSearchMatch, links: [URL] = []) {
    id = match.header.id
    title =
      match.documentTitle ?? match.header.windowTitle.flatMap { $0.isEmpty ? nil : $0 }
      ?? match.header.appName
    kind = match.header.kind
    createdAt = match.header.createdAt
    self.excerpt = match.excerpt
    self.links = links
    imageFilename = match.header.imageFilename
    recordingAvailable = match.header.audioFilename != nil
    retrievalMethod = match.retrieval
  }

  private enum CodingKeys: CodingKey {
    case id, title, kind, createdAt, excerpt, links, imageFilename, savedPassages,
      recordingAvailable,
      retrievalMethod
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    title = try values.decode(String.self, forKey: .title)
    kind = try values.decode(CompanionSkillKind.self, forKey: .kind)
    createdAt = try values.decode(Date.self, forKey: .createdAt)
    excerpt = try values.decode(String.self, forKey: .excerpt)
    links = try values.decode([URL].self, forKey: .links)
    imageFilename = try values.decodeIfPresent(String.self, forKey: .imageFilename)
    savedPassages = try values.decodeIfPresent([VaultEvidencePassage].self, forKey: .savedPassages)
    recordingAvailable = try values.decodeIfPresent(Bool.self, forKey: .recordingAvailable)
    retrievalMethod = try values.decodeIfPresent(
      VaultSearchMatch.Retrieval.self, forKey: .retrievalMethod)
    guard passages.count <= VaultEvidencePassage.maximumPerSource,
      passages.allSatisfy({ $0.reference.location.recordID == id })
    else { throw ConversationStorageError.invalidData }
  }
}
extension ChatSource: SessionAttachmentReference {}
