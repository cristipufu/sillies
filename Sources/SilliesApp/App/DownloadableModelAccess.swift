import Foundation
import SilliesModelStore

struct DownloadableModelAccess<Manifest: ModelArtifactManifest>: Sendable {
  let store: ModelStore
  let catalog: @Sendable () async throws -> [Manifest]
  let selectedID: @Sendable () async -> String
  let select: @Sendable (String) async throws -> Void
  let remove: @Sendable (Manifest) async throws -> Void
  let stop: @Sendable () async -> Void
  let minimumMemoryGB: @Sendable (Manifest) -> Int
}
