import Foundation
import SilliesWriting
import Testing

@testable import SilliesApp

private actor TextAccessFixture: TextDestinationAccess {
  var requiresClipboard = true
  var changed = false
  var nativeInsertions = 0
  func chooseNativeInsertion() { requiresClipboard = false }
  func changeFocus() { changed = true }
  func capture(_ app: FrontmostApplication) -> TextDestination {
    .init(
      id: UUID(), application: app, selection: "")
  }
  func insert(_ text: String, into destination: TextDestination) -> NativeTextInsertion {
    if requiresClipboard { return .requiresClipboard }
    nativeInsertions += 1
    return .inserted
  }
  func validate(_ destination: TextDestination) throws {
    if changed { throw TextAccessError.changed }
  }
  func confirms(_ text: String, at destination: TextDestination) -> Bool { true }
  func release(_ destination: TextDestination) {}
}

private actor PasteFixture: ClipboardPasting {
  var prepared = 0
  var pasted = 0
  var restored = 0
  private var ownsClipboard = false
  func prepare(_ text: String) {
    prepared += 1
    ownsClipboard = true
  }
  func paste(to processID: Int32) { pasted += 1 }
  func restore() -> Bool {
    if ownsClipboard {
      restored += 1
      ownsClipboard = false
    }
    return true
  }
}

private let insertionApp = FrontmostApplication(
  processID: 1, name: "Editor", bundleIdentifier: "test.editor")

@Test func textAccessRejectsInProcessAXBeforeItCanCallAppKitOnAWorker() async {
  let access = AccessibilityTextAccess()
  let ownApplication = FrontmostApplication(
    processID: ProcessInfo.processInfo.processIdentifier, name: "Sillies fixture",
    bundleIdentifier: "test.sillies")
  do {
    _ = try await access.capture(ownApplication)
    Issue.record("In-process AX access must be rejected before invoking AppKit.")
  } catch TextAccessError.unsupported {
  } catch { Issue.record("Unexpected rejection: \(error)") }
}

@Test func insertionRevalidatesAfterPreparingClipboardAndRestoresOnFailure() async throws {
  let access = TextAccessFixture()
  let paste = PasteFixture()
  let service = TextInsertionService(accessibility: access, clipboard: paste)
  let destination = try await service.capture(insertionApp)
  await access.changeFocus()
  await #expect(throws: TextAccessError.self) {
    try await service.insert("text", into: destination)
  }
  #expect(await paste.prepared == 1)
  #expect(await paste.pasted == 0)
  #expect(await paste.restored == 1)
}

@Test func nativeInsertionNeverFallsThroughToAnotherPaste() async throws {
  let access = TextAccessFixture()
  await access.chooseNativeInsertion()
  let paste = PasteFixture()
  let service = TextInsertionService(accessibility: access, clipboard: paste)
  let destination = try await service.capture(insertionApp)
  try await service.insert("line one\nline two", into: destination)
  #expect(await access.nativeInsertions == 1)
  #expect(await paste.prepared == 0)
}

@Test func clipboardFallbackRejectsCommandSeparatorsAndPastesOnlyOnce() async throws {
  let access = TextAccessFixture()
  let paste = PasteFixture()
  let service = TextInsertionService(accessibility: access, clipboard: paste)
  let destination = try await service.capture(insertionApp)
  await #expect(throws: TextAccessError.self) {
    try await service.insert("echo danger\n", into: destination)
  }
  #expect(await paste.prepared == 0)
  try await service.insert("Ștefan, ship API_v2", into: destination)
  #expect(await paste.pasted == 1)
  #expect(await paste.restored == 1)
}
