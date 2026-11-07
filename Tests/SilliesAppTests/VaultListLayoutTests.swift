import AppKit
import SilliesCore
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func vaultListRowsStayCompactWithoutDescriptionOrEmptyPassageSpace() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let model = SessionVaultModel(vault: vault, presentation: .init())
  model.resume()
  defer { model.stop() }
  let titles = [
    "A useful reference", "A research update — with a clear attribution",
    "A longer article title that can occupy two lines without needing an extra description",
    "Notes from the next design review", "An implementation guide", "A saved project",
  ]
  for (index, title) in titles.enumerated() {
    var link = try VaultLink(url: #require(URL(string: "https://example.org/reference/\(index)")))
    link.title = title
    link.description = title + "\n" + String(repeating: "A repeated description. ", count: 20)
    link.previewState = .available
    var metadata = VaultDocumentMetadata(kind: .link, title: title, modifiedAt: Date())
    metadata.link = link
    metadata.isStarred = index == 2
    _ = try await vault.createDocument(metadata: metadata)
  }
  await model.workspace.refresh()
  let header = try #require(model.workspace.records.first { $0.title == titles[2] })
  for width: CGFloat in [250, 320] {
    var heights: [CGFloat] = []
    for excerpt in ["", header.title, String(repeating: "Long search text. ", count: 100)] {
      let variant = VaultDocumentHeader(
        source: header.source, metadata: header.metadata, excerpt: excerpt)
      let host = NSHostingController(
        rootView: VaultDocumentListRow(header: variant, workspace: model.workspace))
      let size = host.sizeThatFits(in: .init(width: width, height: 500))
      #expect(size.width <= width)
      #expect(
        size.height > 30 && size.height <= 70, "Two-line rows must remain compact and readable.")
      heights.append(size.height)
    }
    #expect(Set(heights).count == 1, "Description availability must not change list-row height.")
  }
  let root = SessionVaultView(vault: vault, conversations: nil, model: model)
  for (name, colorScheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
    try await renderSettledSkillInterface(
      root.preferredColorScheme(colorScheme), size: SessionVaultWindowController.minimumSize,
      name: "sillies-vault-tight-list-\(name)")
  }
  await vault.flush()
}
