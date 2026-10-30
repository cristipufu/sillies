import Foundation

package struct ModelArtifact: Codable, Equatable, Sendable {
  package let path: String
  package let url: URL
  package let byteCount: Int64
  package let sha256: String
}
