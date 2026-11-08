import Foundation
import SilliesCore
import Testing

@testable import SilliesVault

@Test(arguments: [
  "https://example.com/project",
  "https://x.com/example/status/123456789",
  "https://www.youtube.com/watch?v=abcdefghijk",
])
func savedLinkToolsKeepCanonicalURLsWhenNotesAreEdited(_ address: String) async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {
    do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
  }
  let library = VaultLibrary(directory: directory)
  let url = try #require(URL(string: address))
  let record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Vault")))
  var metadata = VaultDocumentMetadata(kind: .link, title: "Project reference", modifiedAt: Date())
  metadata.link = try VaultLink(url: url)
  _ = try await library.createDocument(
    record: record, metadata: metadata, notes: "Review this later.")
  let search = VaultSearchTool(library: library)
  let arguments = Data(#"{"query":"","category":"links"}"#.utf8)
  let before = try await library.metrics().loadedBodies
  let result = try await search.call(arguments: arguments)
  #expect(result.sources.map(\.id) == [record.id])
  #expect(result.sources.first?.links == [url])
  #expect(try await library.metrics().loadedBodies == before)

  let location = VaultBlockLocation(recordID: record.id, section: .notes)
  let revision = try #require(try await library.sectionRevision(location))
  _ = try await library.editText(
    .init(
      location: location, expectedRevision: revision, text: "The owner is Mina; no date agreed."),
    at: Date())
  let updated = try await search.call(arguments: arguments)
  #expect(updated.sources.first?.links == [url])
  let readArguments = try JSONEncoder().encode(["recordID": record.id.uuidString, "query": "owner"])
  let read = try await VaultReadTool(library: library).call(arguments: readArguments)
  #expect(read.sources.first?.excerpt.contains("Mina") == true)
  #expect(read.sources.first?.links == [url])

  _ = try await library.editDocument(id: record.id, edit: .moveToTrash, at: Date())
  #expect(try await search.call(arguments: arguments).sources.isEmpty)
  #expect(try await VaultReadTool(library: library).call(arguments: readArguments).sources.isEmpty)
  _ = try await library.editDocument(id: record.id, edit: .restore, at: Date())
  #expect(try await search.call(arguments: arguments).sources.first?.links == [url])
}
