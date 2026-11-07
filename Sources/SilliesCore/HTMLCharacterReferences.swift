/// Decodes terminated HTML references once, preserving unknown or malformed source text.
enum HTMLCharacterReferences {
  private static let maximumReferenceLength = HTMLNamedCharacterReferences.maximumNameLength + 2

  static func decode(_ text: String) -> String {
    var result = ""
    var index = text.startIndex
    while index < text.endIndex {
      if text[index] == "&",
        let end = text[index...].prefix(maximumReferenceLength).firstIndex(of: ";")
      {
        let name = String(text[text.index(after: index)..<end])
        if let decoded = HTMLNamedCharacterReferences.values[name] ?? numericReference(name) {
          result += decoded
          index = text.index(after: end)
          continue
        }
      }
      result.append(text[index])
      index = text.index(after: index)
    }
    return result
  }

  private static func numericReference(_ name: String) -> String? {
    guard name.hasPrefix("#") else { return nil }
    let hexadecimal = name.lowercased().hasPrefix("#x")
    guard let number = UInt32(name.dropFirst(hexadecimal ? 2 : 1), radix: hexadecimal ? 16 : 10),
      let scalar = UnicodeScalar(number)
    else { return nil }
    return String(scalar)
  }
}
