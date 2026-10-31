import Foundation
import SilliesWriting

enum NativeTextInsertion: Sendable { case inserted, requiresClipboard }
protocol TextDestinationAccess: Sendable {
  func capture(_ application: FrontmostApplication) async throws -> TextDestination
  func insert(_ text: String, into destination: TextDestination) async throws -> NativeTextInsertion
  func validate(_ destination: TextDestination) async throws
  func confirms(_ text: String, at destination: TextDestination) async -> Bool
  func release(_ destination: TextDestination) async
}
protocol ClipboardPasting: Sendable {
  func prepare(_ text: String) async throws
  func paste(to processID: Int32) async throws
  func restore() async -> Bool
}

actor TextInsertionService: TextInserting {
  private static let confirmationAttempts = 8
  private static let confirmationInterval: Duration = .milliseconds(100)
  private let accessibility: any TextDestinationAccess
  private let clipboard: any ClipboardPasting
  private var isInserting = false
  init(
    accessibility: any TextDestinationAccess = AccessibilityTextAccess(),
    clipboard: any ClipboardPasting = ClipboardPasteTransaction()
  ) {
    self.accessibility = accessibility
    self.clipboard = clipboard
  }

  func capture(_ application: FrontmostApplication) async throws -> TextDestination {
    guard !isInserting else { throw TextAccessError.failed }
    return try await accessibility.capture(application)
  }

  func insert(_ text: String, into destination: TextDestination) async throws {
    guard !isInserting else { throw TextAccessError.failed }
    isInserting = true
    defer { isInserting = false }
    let outcome: Result<Void, Error>
    do {
      try await insertOnce(text, into: destination)
      outcome = .success(())
    } catch { outcome = .failure(error) }
    let restored = await clipboard.restore()
    await accessibility.release(destination)
    guard restored else { throw TextAccessError.clipboardRestore }
    try outcome.get()
  }

  private func insertOnce(_ text: String, into destination: TextDestination) async throws {
    try Task.checkCancellation()
    let result = try await accessibility.insert(text, into: destination)
    guard case .requiresClipboard = result else { return }
    // Unknown paste targets can execute newline characters. Multiline output needs a native text setter.
    guard !text.contains(where: \.isNewline) else { throw TextAccessError.unsupported }
    try await clipboard.prepare(text)
    try Task.checkCancellation()
    try await accessibility.validate(destination)
    try await clipboard.paste(to: destination.processID)
    var confirmed = false
    for _ in 0..<Self.confirmationAttempts {
      try await Task.sleep(for: Self.confirmationInterval)
      if await accessibility.confirms(text, at: destination) {
        confirmed = true
        break
      }
    }
    guard confirmed else { throw TextAccessError.failed }
  }

  func release(_ destination: TextDestination) async { await accessibility.release(destination) }
}
