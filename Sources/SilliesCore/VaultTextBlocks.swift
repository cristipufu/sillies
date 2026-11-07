import Foundation

/// Unicode-safe blocks keep storage, rendering and indexing work proportional to a visible page.
public enum VaultTextBlocks {
  public static let maximumEditableBlocks = 128
  public static let maximumEditableScalars = maximumEditableBlocks * minimumScalars
  public static let maximumScalars = 2_048
  public static let minimumScalars = maximumScalars / 2

  public static func enumerate(_ text: String, body: (Int, String) throws -> Void) rethrows {
    let scalars = text.unicodeScalars
    var start = scalars.startIndex
    var ordinal = 0
    while start < scalars.endIndex {
      let limit =
        scalars.index(start, offsetBy: maximumScalars, limitedBy: scalars.endIndex)
        ?? scalars.endIndex
      let end = boundary(in: text, from: start, through: limit)
      try body(ordinal, String(scalars[start..<end]))
      start = end
      ordinal += 1
    }
  }

  private static func boundary(
    in text: String, from start: String.Index, through limit: String.Index
  ) -> String.Index {
    let scalars = text.unicodeScalars
    guard limit != scalars.endIndex else { return limit }
    let minimum = scalars.index(start, offsetBy: minimumScalars)
    var cursor = limit
    while cursor > minimum {
      let previous = scalars.index(before: cursor)
      if scalars[previous] == "\n" { return cursor }
      cursor = previous
    }
    cursor = limit
    while cursor > start, cursor.samePosition(in: text) == nil {
      cursor = scalars.index(before: cursor)
    }
    // A pathological single grapheme must still respect the storage/page byte bound.
    return cursor > start ? cursor : limit
  }
}
