import ApplicationServices
import Foundation

/// A bounded scan of one verified call window. Editable subtrees and chat containers are pruned.
final class CallSpeakerTreeRead {
  static let maximumNodes = 1_500
  static let maximumDepth = 32
  static let maximumDuration: TimeInterval = 0.2
  private static let maximumTileTexts = 16
  let deadline: TimeInterval
  private var visited = 0
  private var provider: any CallSpeakerProviding
  private struct Node {
    let element: AXUIElement
    let ancestors: [AXUIElement]
    let scope: CallSpeakerNode.Scope
  }

  init(provider: any CallSpeakerProviding, startedAt: TimeInterval) {
    self.provider = provider
    deadline = startedAt + Self.maximumDuration
  }

  func read(window: AXUIElement) -> CallSpeakerEvidence? {
    var pending = [Node(element: window, ancestors: [], scope: .window)]
    while let node = pending.popLast() {
      guard canRead, node.ancestors.count <= Self.maximumDepth else { return nil }
      visited += 1
      guard let role = CallSpeakerAX.string(.role, of: node.element) else { return nil }
      if Self.excludes(role: role) { continue }
      // Do not copy AXValue here: text values are read only from a provider-approved roster or tile.
      let metadata = CallSpeakerAX.values(
        [.description, .title, .identifier, .classes, .url], of: node.element)
      let identifier = metadata[.identifier] as? String ?? ""
      if Self.excludes(identifier: identifier) { continue }
      let candidate = CallSpeakerNode(
        role: role, description: metadata[.description] as? String,
        title: metadata[.title] as? String, classes: metadata[.classes] as? [String] ?? [],
        url: (metadata[.url] as? URL) ?? (metadata[.url] as? String).flatMap(URL.init(string:)),
        scope: node.scope, readRoster: { self.readRoster(node.element) },
        readSpeakingTile: { self.markedTileTexts(node, maximumAncestorDistance: $0) })
      let traversal = provider.inspect(candidate)
      if traversal == .skip { continue }
      let scope = traversal == .callPage ? .verifiedCallPage : node.scope
      guard
        let children = CallSpeakerAX.elements(
          kAXChildrenAttribute, of: node.element, limit: CallSpeakerAX.maximumChildren)
      else {
        return nil
      }
      let ancestors = node.ancestors + [node.element]
      pending.append(
        contentsOf: children.reversed().map {
          .init(element: $0, ancestors: ancestors, scope: scope)
        })
    }
    return canRead ? provider.evidence : nil
  }

  private var canRead: Bool {
    !Task.isCancelled && visited < Self.maximumNodes
      && ProcessInfo.processInfo.systemUptime < deadline
  }

  private func readRoster(_ outline: AXUIElement) -> CallSpeakerRoster? {
    guard let number = CallSpeakerAX.values([.rowCount], of: outline)[.rowCount] as? NSNumber,
      number.doubleValue.isFinite, let count = Int(exactly: number), count > 0,
      count <= CallSpeakerAX.maximumChildren,
      let rows = CallSpeakerAX.elements(
        kAXRowsAttribute, of: outline, limit: CallSpeakerAX.maximumChildren),
      rows.count == count
    else { return nil }
    var names: [String] = []
    for row in rows {
      guard canRead, CallSpeakerAX.string(.role, of: row) == kAXRowRole,
        let text = firstRosterText(row)
      else { return nil }
      names.append(text)
    }
    guard let final = CallSpeakerAX.values([.rowCount], of: outline)[.rowCount] as? NSNumber,
      final.doubleValue.isFinite, Int(exactly: final) == count
    else { return nil }
    return .init(rows: names, declaredCount: count)
  }

  private func firstRosterText(_ row: AXUIElement) -> String? {
    var pending: [(AXUIElement, Int)] = [(row, 0)]
    while let (element, depth) = pending.popLast() {
      guard canRead, depth <= Self.maximumDepth else { return nil }
      visited += 1
      guard let role = CallSpeakerAX.string(.role, of: element) else { return nil }
      if Self.excludes(role: role) { continue }
      if Self.excludes(identifier: CallSpeakerAX.string(.identifier, of: element) ?? "") {
        continue
      }
      if role == kAXStaticTextRole { return CallSpeakerAX.string(.value, of: element) }
      if role == kAXButtonRole || role == kAXImageRole { continue }
      guard
        let children = CallSpeakerAX.elements(
          kAXChildrenAttribute, of: element, limit: CallSpeakerAX.maximumChildren)
      else { return nil }
      pending.append(contentsOf: children.reversed().map { ($0, depth + 1) })
    }
    return nil
  }

  private func markedTileTexts(_ node: Node, maximumAncestorDistance: Int) -> [String]? {
    // Find the nearest marked tile containing text; never climb outside this verified WebArea.
    let candidates =
      [node.element]
      + node.ancestors.reversed().prefix(min(Self.maximumDepth, max(0, maximumAncestorDistance)))
    for candidate in candidates {
      if CallSpeakerAX.string(.role, of: candidate) == "AXWebArea" { break }
      guard let texts = tileTexts(candidate) else { return nil }
      if !texts.isEmpty { return texts }
    }
    return []
  }
  private func tileTexts(_ root: AXUIElement) -> [String]? {
    var pending: [(AXUIElement, Int)] = [(root, 0)]
    var texts: [String] = []
    while let (element, depth) = pending.popLast() {
      guard canRead, depth <= Self.maximumDepth else { return nil }
      visited += 1
      guard let role = CallSpeakerAX.string(.role, of: element) else { return nil }
      if Self.excludes(role: role) { continue }
      if Self.excludes(identifier: CallSpeakerAX.string(.identifier, of: element) ?? "") {
        continue
      }
      if role == kAXStaticTextRole {
        guard let value = CallSpeakerAX.string(.value, of: element), !value.isEmpty,
          texts.count < Self.maximumTileTexts
        else { return nil }
        texts.append(value)
        continue
      }
      if role == kAXButtonRole || role == kAXImageRole { continue }
      guard
        let children = CallSpeakerAX.elements(
          kAXChildrenAttribute, of: element, limit: CallSpeakerAX.maximumChildren)
      else { return nil }
      pending.append(contentsOf: children.map { ($0, depth + 1) })
    }
    return texts
  }

  static func excludes(role: String) -> Bool {
    [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
  }
  static func excludes(identifier: String) -> Bool {
    guard identifier.utf8.count <= CallSpeakerText.maximumMetadataBytes else { return true }
    let value = identifier.lowercased()
    return ["chat", "message", "composer", "transcript", "caption"].contains(where: value.contains)
  }
}
