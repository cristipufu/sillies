import Foundation

struct WoofTextEncoder {
  private static let characters = Array(
    " abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,!?;:'\"-()&/%$€£@#+=*_<>[]…—")
  private static let vocabulary = Dictionary(
    uniqueKeysWithValues: characters.enumerated().map { ($0.element, Int32($0.offset + 3)) })
  static let vocabularySize = 95
  private static let beginningOfText: Int32 = 1
  private static let unknownCharacter: Int32 = 2

  static func encode(_ text: String) -> [Int32] {
    [beginningOfText] + text.map { vocabulary[$0] ?? unknownCharacter }
  }
}
