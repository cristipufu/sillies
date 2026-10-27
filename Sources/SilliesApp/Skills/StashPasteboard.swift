import AppKit

enum StashPasteboard {
  static let maximumItems = 100
  static let maximumTextCharacters = 1_000_000

  static func items(from pasteboard: NSPasteboard) -> [String] {
    var items: [String] = []
    if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
      items = urls.prefix(maximumItems).map { $0.isFileURL ? $0.path : $0.absoluteString }
    }
    if let text = pasteboard.string(forType: .string)?.trimmingCharacters(
      in: .whitespacesAndNewlines),
      !text.isEmpty, !items.contains(text), items.count < maximumItems
    {
      items.append(String(text.prefix(maximumTextCharacters)))
    }
    return items
  }
}
