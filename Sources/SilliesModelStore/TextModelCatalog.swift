import Foundation

package struct TextModelCatalog: Decodable, Sendable {
  package let manifests: [TextModelManifest]

  package static func bundled() throws -> Self {
    guard
      let url = Bundle.module.url(
        forResource: "text-models", withExtension: "json", subdirectory: "Resources")
    else {
      throw ModelStoreError.invalidManifest
    }
    let result = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    guard Set(result.manifests.map(\.modelID)).count == result.manifests.count else {
      throw ModelStoreError.invalidManifest
    }
    for manifest in result.manifests { try manifest.validate() }
    return result
  }
}
