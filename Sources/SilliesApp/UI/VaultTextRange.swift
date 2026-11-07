import Foundation

/// Validate native UTF-16 ranges without adding offsets that can overflow.
enum VaultTextRange {
  static func contains(_ range: NSRange, inLength length: Int) -> Bool {
    length >= 0 && range.location >= 0 && range.length >= 0
      && range.location <= length && range.length <= length - range.location
  }

  static func clamped(_ range: NSRange, toLength length: Int) -> NSRange {
    guard length >= 0, range.location >= 0, range.length >= 0,
      range.location != NSNotFound
    else { return NSRange(location: 0, length: 0) }
    let start = min(range.location, length)
    return NSRange(location: start, length: min(range.length, length - start))
  }
}
