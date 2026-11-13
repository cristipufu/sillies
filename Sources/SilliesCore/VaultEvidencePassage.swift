import Foundation

/// An exact source slice. Scalar offsets belong to the saved block and section revision.
public struct VaultEvidencePassage: Codable, Hashable, Sendable {
  public static let maximumCharacters = 1_600
  public static let maximumPerSource = 48
  public let reference: VaultSourceReference
  public let scalarOffset: Int
  public let text: String
  public let startSeconds: Double?
  public let speaker: String?

  public init?(block: VaultContentBlock, scalarOffset: Int, text: String) {
    guard block.id > 0, scalarOffset >= 0, !text.isEmpty,
      text.count <= Self.maximumCharacters,
      let start = block.text.unicodeScalars.index(
        block.text.unicodeScalars.startIndex, offsetBy: scalarOffset,
        limitedBy: block.text.unicodeScalars.endIndex),
      block.text.unicodeScalars[start...].starts(with: text.unicodeScalars)
    else { return nil }
    reference = .init(block: block)
    self.scalarOffset = scalarOffset
    self.text = text
    startSeconds = block.startSeconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    speaker = block.speaker
  }

  private enum CodingKeys: CodingKey {
    case reference, scalarOffset, text, startSeconds, speaker
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    reference = try values.decode(VaultSourceReference.self, forKey: .reference)
    scalarOffset = try values.decode(Int.self, forKey: .scalarOffset)
    text = try values.decode(String.self, forKey: .text)
    startSeconds = try values.decodeIfPresent(Double.self, forKey: .startSeconds)
    speaker = try values.decodeIfPresent(String.self, forKey: .speaker)
    guard reference.blockID > 0, reference.location.ordinal >= 0,
      scalarOffset >= 0, scalarOffset <= VaultTextBlocks.maximumScalars,
      !text.isEmpty, text.count <= Self.maximumCharacters,
      text.unicodeScalars.count <= VaultTextBlocks.maximumScalars,
      startSeconds.map({ $0.isFinite && $0 >= 0 }) != false
    else { throw ConversationStorageError.invalidData }
  }

  public func prefix(_ characters: Int) -> Self? {
    guard characters > 0 else { return nil }
    return .init(original: self, text: String(text.prefix(characters)))
  }

  public func contains(_ passage: Self) -> Bool {
    guard reference == passage.reference, passage.scalarOffset >= scalarOffset else { return false }
    let offset = passage.scalarOffset - scalarOffset
    guard offset <= text.unicodeScalars.count else { return false }
    return text.unicodeScalars.dropFirst(offset).starts(with: passage.text.unicodeScalars)
  }

  private init(original: Self, text: String) {
    reference = original.reference
    scalarOffset = original.scalarOffset
    self.text = text
    startSeconds = original.startSeconds
    speaker = original.speaker
  }

  /// Never trusts a persisted offset, revision or quotation without checking current text.
  public func range(in block: VaultContentBlock) -> Range<String.Index>? {
    guard reference.blockID == block.id,
      reference.location.recordID == block.location.recordID,
      reference.location.section == block.location.section,
      reference.revision == block.revision,
      scalarOffset >= 0, !text.isEmpty, text.count <= Self.maximumCharacters,
      let start = block.text.unicodeScalars.index(
        block.text.unicodeScalars.startIndex, offsetBy: scalarOffset,
        limitedBy: block.text.unicodeScalars.endIndex),
      let end = block.text.unicodeScalars.index(
        start, offsetBy: text.unicodeScalars.count,
        limitedBy: block.text.unicodeScalars.endIndex),
      String(block.text.unicodeScalars[start..<end]) == text
    else { return nil }
    return start..<end
  }
}
