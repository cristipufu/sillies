import Foundation
import Observation
import SilliesCore

/// Picking a destination and appending a quote share one lifetime; failures retain the quotation.
@MainActor @Observable final class VaultQuoteDestinationModel {
  private let vault: SessionVaultStore
  let passage: VaultQuotedPassage
  var query = ""
  private(set) var candidates: [VaultDocumentHeader] = []
  private(set) var isSaving = false
  private(set) var error: String?
  private var request = UUID()

  init(vault: SessionVaultStore, passage: VaultQuotedPassage) {
    self.vault = vault
    self.passage = passage
  }
  func search() async {
    let token = UUID()
    request = token
    do {
      if !query.isEmpty { try await Task.sleep(for: .milliseconds(140)) }
      let page = try await vault.library.workspacePage(
        .init(text: query, ordering: query.isEmpty ? .newest : .relevance))
      guard request == token, !Task.isCancelled else { return }
      candidates = page.records
      error = nil
    } catch is CancellationError { return } catch {
      guard request == token, !Task.isCancelled else { return }
      self.error = error.localizedDescription
    }
  }

  func save(to destination: UUID?) async -> VaultBlockLocation? {
    guard !isSaving else { return nil }
    isSaving = true
    defer { isSaving = false }
    do {
      try Task.checkCancellation()
      if let destination {
        let location = try await vault.library.appendQuote(passage, to: destination, at: Date())
        vault.workspaceChanged([destination])
        return location
      }
      let header = try await vault.createDocument(
        metadata: .init(kind: .note, title: passage.title, modifiedAt: Date()),
        notes: passage.markdown)
      return .init(recordID: header.id, section: .notes)
    } catch is CancellationError { return nil } catch {
      self.error = error.localizedDescription
      fputs("Vault quotation save failed: \(error)\n", stderr)
      return nil
    }
  }
}
