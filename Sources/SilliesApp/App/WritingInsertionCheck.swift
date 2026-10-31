import AppKit
import SilliesWriting

/// Opt-in native check, confined to an editor owned by this process. Never records audio.
@MainActor enum WritingInsertionCheck {
  private static let sample = "Ștefan ships API_v2 at 16:30."

  static func run() async {
    let previousApplication = NSWorkspace.shared.frontmostApplication
    let fixture = WritingFixtureProcess()
    do {
      guard let executable = Bundle.main.executableURL else {
        throw CheckFailure(message: "The fixture executable was not found.")
      }
      let processID = try await fixture.start(executable: executable)
      let application = FrontmostApplication(
        processID: processID, name: "Writing fixture",
        bundleIdentifier: Bundle.main.bundleIdentifier)
      _ = try await fixture.request(.init(text: "", caret: 0))
      try await waitForFocus(processID)
      try await verifyNativeInsertion(fixture: fixture, application: application)
      try await verifyChangedCaret(fixture: fixture, application: application)
      try await verifyClipboardInsertion(fixture: fixture, application: application)
      print(
        "WRITING INSERTION CHECK PASSED: native insertion, changed caret, clipboard paste, Romanian/code preservation"
      )
      await fixture.stop()
      previousApplication?.activate(options: [])
      NSApp.terminate(nil)
    } catch {
      await fixture.stop()
      previousApplication?.activate(options: [])
      fputs("WRITING INSERTION CHECK FAILED: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }

  private static func waitForFocus(_ processID: Int32) async throws {
    for _ in 0..<40 {
      if NSWorkspace.shared.frontmostApplication?.processIdentifier == processID { return }
      try await Task.sleep(for: .milliseconds(50))
    }
    throw CheckFailure(message: "The fixture could not acquire focus.")
  }

  private static func verifyNativeInsertion(
    fixture: WritingFixtureProcess, application: FrontmostApplication
  )
    async throws
  {
    _ = try await fixture.request(.init(text: "Before: ", caret: "Before: ".utf16.count))
    let insertion = TextInsertionService()
    let destination = try await insertion.capture(application)
    try await insertion.insert(sample, into: destination)
    guard try await fixture.request(.init()).text == "Before: " + sample else {
      throw CheckFailure(message: "Native insertion changed or lost text.")
    }
  }

  private static func verifyChangedCaret(
    fixture: WritingFixtureProcess, application: FrontmostApplication
  )
    async throws
  {
    let insertion = TextInsertionService()
    let destination = try await insertion.capture(application)
    let before = try await fixture.request(.init(caret: 0)).text
    do {
      try await insertion.insert("must not appear", into: destination)
      throw CheckFailure(message: "Insertion accepted a changed caret.")
    } catch TextAccessError.changed {}
    guard try await fixture.request(.init()).text == before else {
      throw CheckFailure(message: "Changed-focus insertion mutated text.")
    }
  }

  private static func verifyClipboardInsertion(
    fixture: WritingFixtureProcess, application: FrontmostApplication
  ) async throws {
    _ = try await fixture.request(.init(text: "Paste: ", caret: "Paste: ".utf16.count))
    let insertion = TextInsertionService(accessibility: ClipboardOnlyTextAccess())
    let destination = try await insertion.capture(application)
    try await insertion.insert(sample, into: destination)
    guard try await fixture.request(.init()).text == "Paste: " + sample else {
      throw CheckFailure(message: "Clipboard insertion changed or lost text.")
    }
  }

  private struct CheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }
}

private actor ClipboardOnlyTextAccess: TextDestinationAccess {
  private let base = AccessibilityTextAccess()
  func capture(_ application: FrontmostApplication) async throws -> TextDestination {
    try await base.capture(application)
  }
  func insert(_ text: String, into destination: TextDestination) async throws -> NativeTextInsertion
  {
    try await base.validate(destination)
    return .requiresClipboard
  }
  func validate(_ destination: TextDestination) async throws {
    try await base.validate(destination)
  }
  func confirms(_ text: String, at destination: TextDestination) async -> Bool {
    await base.confirms(text, at: destination)
  }
  func release(_ destination: TextDestination) async { await base.release(destination) }
}
