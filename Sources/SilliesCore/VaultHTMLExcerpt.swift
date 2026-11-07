import Foundation

/// Extracts display text from bounded oEmbed fragments. It does not load or render HTML.
public enum VaultHTMLExcerpt {
  private static let separators: Set<String> = [
    "p", "/p", "br", "br/", "/blockquote", "div", "/div",
  ]
  private static let entities = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
  ]

  public static func text(_ html: String) -> String {
    var output = ""
    var index = html.startIndex
    var ignoredTag: String?
    while index < html.endIndex {
      let character = html[index]
      if character == "<", let end = tagEnd(in: html, after: index) {
        let raw = html[html.index(after: index)..<end].trimmingCharacters(
          in: .whitespacesAndNewlines
        ).lowercased()
        let name = String(raw.prefix { !$0.isWhitespace })
        if let ignored = ignoredTag {
          if name == "/" + ignored { ignoredTag = nil }
        } else if name == "script" || name == "style" {
          ignoredTag = name
        } else if separators.contains(name), !output.hasSuffix("\n") {
          output += "\n"
        }
        index = html.index(after: end)
        continue
      }
      if ignoredTag == nil { output.append(character) }
      index = html.index(after: index)
    }
    return decodeEntities(output).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func tagEnd(in text: String, after start: String.Index) -> String.Index? {
    var quote: Character?
    var index = text.index(after: start)
    while index < text.endIndex {
      let character = text[index]
      if let current = quote {
        if character == current { quote = nil }
      } else if character == "\"" || character == "'" {
        quote = character
      } else if character == ">" {
        return index
      }
      index = text.index(after: index)
    }
    return nil
  }

  private static func decodeEntities(_ text: String) -> String {
    var result = ""
    var index = text.startIndex
    while index < text.endIndex {
      if text[index] == "&", let end = text[index...].prefix(16).firstIndex(of: ";") {
        let name = String(text[text.index(after: index)..<end])
        if let decoded = entities[name] ?? numericEntity(name) {
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

  private static func numericEntity(_ name: String) -> String? {
    guard name.hasPrefix("#") else { return nil }
    let hexadecimal = name.lowercased().hasPrefix("#x")
    guard let number = UInt32(name.dropFirst(hexadecimal ? 2 : 1), radix: hexadecimal ? 16 : 10),
      let scalar = UnicodeScalar(number)
    else { return nil }
    return String(scalar)
  }
}
