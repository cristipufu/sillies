import AppKit
import SilliesCore
import Testing

@testable import SilliesApp

@MainActor final class VaultNativeFixture {
  let vault: SessionVaultStore
  let owner: SessionVaultWindowController
  let id: UUID
  private let directory: URL
  private let previousApplication = NSWorkspace.shared.frontmostApplication
  private let previousPolicy = NSApplication.shared.activationPolicy()
  private let previousMenu = NSApplication.shared.mainMenu

  private init(directory: URL, vault: SessionVaultStore, id: UUID) {
    self.directory = directory
    self.vault = vault
    self.id = id
    owner = SessionVaultWindowController(
      vault: vault, appearance: ThemeEnvironment(), services: .init())
  }

  static func make() async throws -> VaultNativeFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let vault = SessionVaultStore(directory: directory)
    await vault.waitUntilLoaded()
    vault.suspendBackgroundProcessing()
    let header = try await vault.createDocument(
      metadata: .init(kind: .note, title: "Native interaction fixture", modifiedAt: Date()),
      notes: String(repeating: "Navigation, keyboard focus and readable notes.\n", count: 120))
    let fixture = VaultNativeFixture(directory: directory, vault: vault, id: header.id)
    do {
      NSApp.setActivationPolicy(.accessory)
      NSApp.mainMenu = ApplicationMenu.make()
      fixture.owner.show(.record(header.id))
      try await fixture.waitForDocument()
      try DisplayFrameSequence.presentCreatedWindows()
      return fixture
    } catch {
      fixture.close()
      throw error
    }
  }

  func waitForDocument() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    let workspace = owner.model.workspace
    while workspace.document.header?.id != id || workspace.isOpening || workspace.document.isLoading
    {
      guard ContinuousClock.now < deadline else { throw CocoaError(.executableRuntimeMismatch) }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  func close() {
    owner.close()
    NSApp.mainMenu = previousMenu
    NSApp.setActivationPolicy(previousPolicy)
    previousApplication?.activate(options: [])
    removeTestFile(at: directory)
  }

  func textViews(in view: NSView) -> [NSTextView] {
    (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap { textViews(in: $0) }
  }

  func command(_ character: String, keyCode: UInt16) throws -> NSEvent {
    let window = try #require(owner.window)
    let windowID = try #require(window.windowServerID)
    return try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
        windowNumber: Int(windowID), context: nil, characters: character,
        charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode))
  }

  func recordTiming(samples: [Double], intervals: [Double]) throws {
    guard let path = ProcessInfo.processInfo.environment["SILLIES_VAULT_NATIVE_TIMING"] else {
      return
    }
    struct Timing: Encodable {
      let operationMilliseconds: [Double]
      let displayIntervalMilliseconds: [Double]
    }
    let result = Timing(operationMilliseconds: samples, displayIntervalMilliseconds: intervals)
    try JSONEncoder().encode(result).write(to: URL(fileURLWithPath: path), options: .atomic)
  }

  static func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
  }
}
