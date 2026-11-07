import Foundation

public struct VaultQuotedPassage: Equatable, Sendable {
  public static let maximumScalars = 32_768
  public let reference: VaultSourceReference
  public let title: String
  public let text: String

  public init(reference: VaultSourceReference, title: String, text: String) throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      text.unicodeScalars.count <= Self.maximumScalars,
      title.unicodeScalars.count <= VaultDocumentMetadata.maximumTitleScalars
    else { throw VaultEditingError.invalidValue }
    self.reference = reference
    self.title = title
    self.text = text
  }

  public var markdown: String {
    let quoted = text.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
    let label = title.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
      .replacingOccurrences(of: "\n", with: " ")
    return "\(quoted)\n\n[\(label)](\(reference.link))\n"
  }
}
