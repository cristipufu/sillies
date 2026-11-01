import Foundation
import SilliesCore

/// A model may require a separately versioned codec or pronunciation dictionary.
/// Every component is pinned and installed as part of the same verified transaction.
package struct TTSModelManifest: Codable, Equatable, ModelArtifactManifest {
  package struct Component: Codable, Equatable, Sendable {
    package let directory: String
    package let repository: String
    package let revision: String
    package let sourceDirectory: String
  }

  package let model: TTSModelDescriptor
  package let components: [Component]
  package let artifacts: [ModelArtifact]
  package var modelID: String { model.id }
  package var revision: String { model.revision }

  package func validate() throws {
    try validateArtifacts()
    guard ModelFiles.isSafeComponent(model.providerID),
      model.minimumMemoryGB > 0, !model.languages.isEmpty, !model.voices.isEmpty,
      model.outputSampleRate.map(TTSModelDescriptor.supportedOutputSampleRates.contains) ?? true,
      Set(model.voices.map(\.id)).count == model.voices.count,
      model.voices.allSatisfy({ ModelFiles.isSafeComponent($0.id) && !$0.languages.isEmpty }),
      components.contains(where: { $0.revision == revision })
    else { throw ModelStoreError.invalidManifest }
    for component in components {
      guard component.directory.isEmpty || ModelFiles.isSafeRelativePath(component.directory),
        component.sourceDirectory.isEmpty
          || ModelFiles.isSafeRelativePath(component.sourceDirectory),
        HubModelReference.isRevision(component.revision)
      else { throw ModelStoreError.invalidManifest }
    }
    for artifact in artifacts {
      let reference = try HubModelReference(artifact.url)
      guard
        components.contains(where: {
          let sourcePrefix = $0.sourceDirectory.isEmpty ? "" : $0.sourceDirectory + "/"
          guard reference.path.hasPrefix(sourcePrefix) else { return false }
          let relative = String(reference.path.dropFirst(sourcePrefix.count))
          let path = $0.directory.isEmpty ? relative : $0.directory + "/" + relative
          return reference.repository == $0.repository && reference.revision == $0.revision
            && artifact.path == path
        })
      else { throw ModelStoreError.invalidManifest }
    }
  }
}
