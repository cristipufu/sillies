import Foundation

/// A single native text edit preserves the unchanged prefix/suffix and their selected words.
struct ChatTextReplacement {
  let previousRange: NSRange
  let nextRange: NSRange
  private let previousLength: Int
  private let nextLength: Int

  init(previous: String, next: String) {
    let previous = previous as NSString
    let next = next as NSString
    previousLength = previous.length
    nextLength = next.length
    var prefix = 0
    while prefix < min(previous.length, next.length),
      previous.character(at: prefix) == next.character(at: prefix)
    {
      prefix += 1
    }
    prefix = min(
      Self.composedStart(prefix, in: previous), Self.composedStart(prefix, in: next))
    var suffix = 0
    while suffix < min(previous.length, next.length) - prefix,
      previous.character(at: previous.length - suffix - 1)
        == next.character(at: next.length - suffix - 1)
    {
      suffix += 1
    }
    suffix = min(
      Self.composedSuffix(suffix, in: previous), Self.composedSuffix(suffix, in: next))
    previousRange = NSRange(location: prefix, length: previous.length - prefix - suffix)
    nextRange = NSRange(location: prefix, length: next.length - prefix - suffix)
  }

  func selection(_ range: NSRange) -> NSRange {
    guard range.location >= 0, range.location != NSNotFound, range.length >= 0 else {
      return NSRange(location: 0, length: 0)
    }
    let location = min(range.location, previousLength)
    let length = min(range.length, previousLength - location)
    let start = min(nextLength, position(location))
    let end = min(nextLength, position(location + length))
    return NSRange(location: start, length: max(0, end - start))
  }

  private func position(_ offset: Int) -> Int {
    if offset <= previousRange.location { return offset }
    if offset >= NSMaxRange(previousRange) {
      return offset - previousRange.length + nextRange.length
    }
    return nextRange.location + min(offset - previousRange.location, nextRange.length)
  }

  private static func composedStart(_ offset: Int, in text: NSString) -> Int {
    offset < text.length ? text.rangeOfComposedCharacterSequence(at: offset).location : offset
  }

  private static func composedSuffix(_ length: Int, in text: NSString) -> Int {
    guard length > 0 else { return 0 }
    let start = text.length - length
    let range = text.rangeOfComposedCharacterSequence(at: start)
    return range.location == start ? length : text.length - NSMaxRange(range)
  }
}
