import AppKit
import Observation
import SilliesCore
import SilliesVault

@MainActor @Observable final class VaultFileReferencesModel {
  private let library: VaultLibrary
  private var generation = UUID()
  private var recordID: UUID?
  private(set) var references: [VaultFileReference] = []
  private(set) var isLoading = false
  private(set) var error: String?
  init(library: VaultLibrary) { self.library = library }
  func load(id: UUID) async {
    generation = UUID()
    if recordID != id { references = [] }
    recordID = id
    error = nil
    isLoading = true
    let token = generation
    defer { if token == generation { isLoading = false } }
    do {
      let references = try await library.fileReferences(id: id)
      guard token == generation, !Task.isCancelled else { return }
      self.references = references
    } catch is CancellationError { return } catch {
      guard token == generation else { return }
      self.error = error.localizedDescription
    }
  }
  func open(_ reference: VaultFileReference) async {
    let token = generation
    do {
      _ = try await NSWorkspace.shared.open(reference.url, configuration: .init())
    } catch {
      guard token == generation, !Task.isCancelled else { return }
      self.error = String(
        localized:
          "This file could not be opened. If it moved, choose Relink. \(error.localizedDescription)"
      )
    }
  }
  func reveal(_ reference: VaultFileReference) {
    NSWorkspace.shared.activateFileViewerSelecting([reference.url])
  }
  func stop() {
    generation = UUID()
    recordID = nil
    isLoading = false
    references = []
    error = nil
  }
}
