import Foundation
import Observation
import SilliesCore
import SilliesVault

@MainActor @Observable final class VaultSourceFacetModel {
  private let library: VaultLibrary
  private let additionalChoices: ((String) async throws -> [VaultSourceFacet])?
  let kind: VaultSourceFacet.Kind
  private(set) var choices: [VaultSourceFacet] = []
  private(set) var isLoading = false
  private(set) var error: String?
  private var request = UUID()

  init(
    library: VaultLibrary, kind: VaultSourceFacet.Kind,
    additionalChoices: ((String) async throws -> [VaultSourceFacet])?
  ) {
    self.library = library
    self.kind = kind
    self.additionalChoices = additionalChoices
  }

  func search(_ text: String) async {
    let token = UUID()
    request = token
    isLoading = true
    defer { if token == request { isLoading = false } }
    do {
      if !text.isEmpty { try await Task.sleep(for: .milliseconds(120)) }
      let stored = try await library.sourceFacets(kind, matching: text)
      let extra = try await additionalChoices?(text) ?? []
      var unique = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      for choice in extra { unique[choice.id] = choice }
      let choices = unique.values.sorted {
        $0.title.localizedStandardCompare($1.title) == .orderedAscending
      }
      guard token == request, !Task.isCancelled else { return }
      self.choices = Array(choices.prefix(VaultSourceFacet.maximumChoices))
      error = nil
    } catch is CancellationError { return } catch {
      guard token == request, !Task.isCancelled else { return }
      self.error = error.localizedDescription
    }
  }
}
