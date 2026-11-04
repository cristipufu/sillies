import Foundation

package struct SearchModelCatalog: Decodable, Sendable {
  package let manifests: [SearchModelManifest]
  package static func bundled() throws -> Self {
    guard
      let url = Bundle.module.url(
        forResource: "search-models", withExtension: "json", subdirectory: "Resources")
    else { throw ModelStoreError.invalidManifest }
    let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    guard Set(catalog.manifests.map(\.modelID)).count == catalog.manifests.count else {
      throw ModelStoreError.invalidManifest
    }
    for manifest in catalog.manifests { try manifest.validate() }
    return catalog
  }
}
