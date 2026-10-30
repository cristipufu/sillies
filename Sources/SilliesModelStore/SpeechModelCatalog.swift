import Foundation
import SilliesCore

package struct SpeechModelCatalog: Sendable {
  package let manifests: [SpeechModelManifest]
  package var models: [SpeechModelDescriptor] { [.apple] + manifests.map(\.model) }

  package init(manifests: [SpeechModelManifest]) throws {
    guard Set(manifests.map { $0.model.id }).count == manifests.count else {
      throw ModelStoreError.invalidManifest
    }
    for manifest in manifests { try manifest.validate() }
    self.manifests = manifests
  }

  package static func bundled() throws -> SpeechModelCatalog {
    let packaged = Bundle.main.resourceURL?.appendingPathComponent(
      "Sillies_SilliesModelStore.bundle")
    let bundle = packaged.flatMap { Bundle(url: $0) } ?? Bundle.module
    guard
      let url = bundle.url(
        forResource: "speech-models", withExtension: "json", subdirectory: "Resources")
    else {
      throw ModelStoreError.invalidManifest
    }
    return try SpeechModelCatalog(
      manifests: JSONDecoder().decode([SpeechModelManifest].self, from: Data(contentsOf: url)))
  }

  package func manifest(for id: String) throws -> SpeechModelManifest {
    guard let manifest = manifests.first(where: { $0.model.id == id }) else {
      throw ModelStoreError.unknownModel
    }
    return manifest
  }
}
