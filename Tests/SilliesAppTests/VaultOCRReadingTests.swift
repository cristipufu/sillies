import AppKit
import SilliesCore
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func vaultOCRDisplaysRecognizedInlineWordsAsCompleteReadingLines() async throws {
  let text = try await WindowTextRecognition.recognize(fragmentedScreenshotFixture())
  let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
  #expect(lines.contains("Plan the next release."))
  #expect(lines.contains("Files Search Notes"))
  #expect(lines.contains("Keep every word on the same line."))
  #expect(!lines.contains("Plan") && !lines.contains("next"))
  try await renderRecognizedScreenshot(text, name: "sillies-vault-ocr-inline-words")

  // Opt-in visual review uses the real native OCR-to-Vault path without storing private captures in fixtures.
  let environment = ProcessInfo.processInfo.environment
  if environment["SILLIES_SKILL_UI_SNAPSHOTS"] == "1",
    let path = environment["SILLIES_OCR_REVIEW_IMAGE"]
  {
    let reviewed = try await WindowTextRecognition.recognize(URL(fileURLWithPath: path))
    try await renderRecognizedScreenshot(reviewed, name: "sillies-vault-ocr-reviewed-image")
  }
}

@MainActor private func renderRecognizedScreenshot(_ text: String, name: String) async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  var record = SessionRecord(
    kind: .snap,
    origin: .init(characterID: "kiko", characterName: "Kiko", source: .init(appName: "Screenshot")),
    content: .init(text: .init(extractedText: text)))
  record.screenshotTextState = .complete
  vault.add(record)
  await vault.flush()
  let model = SessionVaultModel(vault: vault, presentation: .init())
  model.resume()
  defer { model.stop() }
  await model.workspace.refresh()
  model.workspace.visit(.init(recordID: record.id, section: .screenshotText))
  let deadline = ContinuousClock.now + .seconds(3)
  while model.workspace.isOpening, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
  try #require(!model.workspace.isOpening)
  #expect(model.workspace.document.pane == .text(.screenshotText))
  #expect(model.workspace.document.editor.text == text)
  try await renderSettledSkillInterface(
    SessionVaultView(vault: vault, conversations: nil, model: model).preferredColorScheme(.light),
    size: .init(width: 1180, height: 820), name: name)
}

@MainActor private func fragmentedScreenshotFixture() throws -> CGImage {
  let image = NSImage(size: .init(width: 1100, height: 600))
  image.lockFocus()
  NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
  NSBezierPath(rect: .init(x: 0, y: 0, width: 1100, height: 600)).fill()
  let font = NSFont.monospacedSystemFont(ofSize: 24, weight: .regular)
  func draw(_ text: String, at point: NSPoint, color: NSColor = .white) {
    (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
  }
  draw("Release planning", at: .init(x: 65, y: 540))
  draw("Files", at: .init(x: 65, y: 490), color: .lightGray)
  draw("Search", at: .init(x: 260, y: 490), color: .lightGray)
  draw("Notes", at: .init(x: 450, y: 490), color: .lightGray)
  var x: CGFloat = 65
  for (word, color) in [
    ("Plan", NSColor.white), ("the", NSColor.systemTeal), ("next", NSColor.systemYellow),
    ("release.", NSColor.white),
  ] {
    draw(word, at: .init(x: x, y: 390), color: color)
    x += ((word + " ") as NSString).size(withAttributes: [.font: font]).width
  }
  draw("Keep every word on the same line.", at: .init(x: 95, y: 355))
  draw("func render() {", at: .init(x: 65, y: 260), color: .systemTeal)
  draw("showImage()", at: .init(x: 120, y: 225))
  draw("}", at: .init(x: 65, y: 190), color: .systemTeal)
  draw("Review the result together.", at: .init(x: 65, y: 90))
  image.unlockFocus()
  return try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
}
