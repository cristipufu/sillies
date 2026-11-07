import AppKit
import SilliesCore
import SilliesVault
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func vaultScreenshotOpensTheImageAndSearchStillOpensMatchingText() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  var record = screenshotRecord()
  record.screenshotTextState = .complete
  vault.add(record, image: try screenshotFixture())
  await vault.flush()
  let reopened = SessionVaultStore(directory: directory)
  await reopened.waitUntilLoaded()
  reopened.suspendBackgroundProcessing()
  let model = SessionVaultModel(vault: reopened, presentation: .init())
  model.resume()
  defer { model.stop() }
  await model.workspace.refresh()
  model.workspace.select(record.id)
  try await awaitScreenshot {
    model.workspace.document.header?.id == record.id && !model.workspace.document.isLoading
  }
  let document = model.workspace.document
  #expect(document.pane == .screenshot)
  let source = try #require(document.header?.source)
  try await awaitScreenshot {
    if case .available = reopened.imageState(for: source) { true } else { false }
  }
  let root = SessionVaultView(vault: reopened, conversations: nil, model: model)
  for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
    try await renderSettledSkillInterface(
      root.preferredColorScheme(scheme),
      size: .init(width: 1060, height: 700), name: "sillies-vault-screenshot-\(name)")
  }
  #expect(await document.selectPane(.text(.screenshotText)))
  #expect(document.editor.text == record.extractedText)
  try await renderSettledSkillInterface(
    root.preferredColorScheme(.light),
    size: SessionVaultWindowController.minimumSize, name: "sillies-vault-screenshot-text")
  #expect(await document.selectPane(.files))
  #expect(document.pane == .files)
  #expect(await document.selectPane(.text(.notes)))
  document.editor.replaceText("My annotation")
  #expect(await document.selectPane(.screenshot))
  #expect(!document.editor.isDirty)
  await document.open(record.id, match: .init(recordID: record.id, section: .screenshotText))
  #expect(document.pane == .text(.screenshotText))
  let note = try await reopened.createDocument(
    metadata: .init(kind: .note, title: "A note", modifiedAt: Date()), notes: "Text only")
  await document.open(note.id)
  #expect(document.pane == .text(.notes) && !document.panes.contains(.screenshot))
  #expect(!(await document.selectPane(.screenshot)))
  await reopened.flush()
}

@Test @MainActor func vaultScreenshotFailuresCanBeRetriedWithoutAnEndlessSpinner() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  var record = screenshotRecord()
  record.imageFilename = "restored-image.png"
  vault.add(record)
  await vault.flush()
  let document = VaultDocumentModel(vault: vault)
  await document.open(record.id)
  defer { document.stop() }
  let source = try #require(document.header?.source)
  try await awaitScreenshot {
    if case .unavailable = vault.imageState(for: source) { true } else { false }
  }
  let image = try screenshotFixture()
  let url = try #require(vault.imageURL(for: source))
  try await Task.detached {
    let png = try #require(VaultImageCodec.encodePNGData(from: image))
    try png.write(to: url, options: .atomic)
  }.value
  vault.prepareImage(for: source)
  try await awaitScreenshot {
    if case .available = vault.imageState(for: source) { true } else { false }
  }
  let cache = VaultImageCache()
  for index in 0..<100 { cache.recordFailure(named: "missing-\(index)") }
  #expect(!cache.isUnavailable("missing-0") && cache.isUnavailable("missing-99"))
  #expect(cache.totalBytes == 0)
}

@Test @MainActor func vaultScreenshotNavigationRestoresTheVisiblePane() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  var screenshot = screenshotRecord()
  screenshot.screenshotTextState = .complete
  vault.add(screenshot, image: try screenshotFixture())
  await vault.flush()
  let note = try await vault.createDocument(
    metadata: .init(kind: .note, title: "A note", modifiedAt: Date()), notes: "Remember this")
  let workspace = VaultWorkspaceModel(vault: vault)
  workspace.resume()
  defer { workspace.stop() }
  await workspace.refresh()
  workspace.select(screenshot.id)
  try await awaitScreenshot { !workspace.isOpening }
  #expect(workspace.document.pane == .screenshot)
  #expect(workspace.document.visibleTextLocation == nil)
  workspace.select(note.id)
  try await awaitScreenshot { !workspace.isOpening }
  workspace.goBack()
  try await awaitScreenshot { !workspace.isOpening }
  #expect(workspace.document.header?.id == screenshot.id)
  #expect(workspace.document.pane == .screenshot)
  workspace.showStorage()
  workspace.showLibrary()
  try await awaitScreenshot { !workspace.isOpening }
  #expect(workspace.document.pane == .screenshot)
  workspace.visit(.init(recordID: screenshot.id, section: .screenshotText))
  try await awaitScreenshot { !workspace.isOpening }
  #expect(workspace.document.pane == .text(.screenshotText))
  #expect(workspace.document.visibleTextLocation?.section == .screenshotText)
  #expect(await workspace.document.selectPane(.files))
  workspace.select(note.id)
  try await awaitScreenshot { !workspace.isOpening }
  workspace.goBack()
  try await awaitScreenshot { !workspace.isOpening }
  #expect(workspace.document.pane == .files)
  #expect(workspace.document.visibleTextLocation == nil)
  workspace.stop()
  workspace.resume()
  try await awaitScreenshot { !workspace.isOpening }
  #expect(workspace.document.pane == .files)
  workspace.goForward()
  try await awaitScreenshot { !workspace.isOpening }
  #expect(workspace.document.header?.id == note.id)
  #expect(workspace.document.pane == .text(.notes))
}

@Test @MainActor func vaultScreenshotRecognitionCompletionRefreshesTheVisibleText() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  var record = screenshotRecord()
  record.imageFilename = "pending.png"
  record.screenshotTextState = .pending
  vault.add(record)
  await vault.flush()
  let document = VaultDocumentModel(vault: vault)
  await document.open(record.id)
  defer { document.stop() }
  #expect(await document.selectSection(.screenshotText))
  _ = try await vault.edit(
    id: record.id,
    .completeScreenshot(
      text: "Fresh\n    readable text", revision: record.processingRevision.screenshot))
  await document.refreshHeader()
  #expect(document.editor.text == "Fresh\n    readable text")
  document.editor.replaceText("My own correction")
  await document.flush()
  _ = try await vault.edit(id: record.id, .retryScreenshot)
  let latest = try #require(try await vault.record(id: record.id))
  await document.refreshHeader()
  _ = try await vault.edit(
    id: record.id,
    .completeScreenshot(text: "Recognition retry", revision: latest.processingRevision.screenshot))
  await document.refreshHeader()
  #expect(document.editor.text == "My own correction")
  await vault.flush()
}

@Test @MainActor func nativeScreenshotOCRPreservesVisibleTextAndParagraphSeparation() async throws {
  let text = try await WindowTextRecognition.recognize(screenshotFixture())
  #expect(text.contains("Project Mercury"))
  #expect(text.contains("capture viewer") && text.contains("searchable"))
  #expect(text.contains("\n\n"))
  let image = try screenshotFixture()
  let cancellation = Task { try await WindowTextRecognition.recognize(image) }
  cancellation.cancel()
  await #expect(throws: CancellationError.self) { try await cancellation.value }
}

@MainActor private func screenshotFixture() throws -> CGImage {
  let image = NSImage(size: .init(width: 1000, height: 650))
  image.lockFocus()
  NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.95, alpha: 1).setFill()
  NSBezierPath(rect: .init(x: 0, y: 0, width: 1000, height: 650)).fill()
  let lines: [(String, CGFloat, CGFloat)] = [
    ("Project Mercury", 540, 34),
    ("A little space for our next ideas.", 470, 24),
    ("Next steps", 350, 28),
    ("• Improve the capture viewer", 290, 24),
    ("• Keep source text searchable", 245, 24),
    ("Review together on Friday.", 120, 24),
  ]
  for (text, y, size) in lines {
    (text as NSString).draw(
      at: .init(x: 65, y: y),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.darkGray,
      ])
  }
  image.unlockFocus()
  return try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
}

private func screenshotRecord() -> SessionRecord {
  .init(
    kind: .snap,
    origin: .init(
      characterID: "kiko", characterName: "Kiko", source: .init(appName: "Project Mercury")),
    content: .init(
      text: .init(
        extractedText:
          "Project Mercury\n\nNext steps\n• Improve the capture viewer\n• Keep source text searchable"
      ),
      notes: .init(summary: "Captured window snapshot.")))
}

@MainActor private func awaitScreenshot(_ ready: () -> Bool) async throws {
  let deadline = ContinuousClock.now + .seconds(3)
  while !ready(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
  try #require(ready())
}
