import Foundation

package struct SearchModelDescriptor: Codable, Equatable, Sendable {
  package let id: String
  package let revision: String
  package let name: String
  package let providerID: String
  package let sourceURL: URL
  package let minimumMemoryGB: Int
  package let license: String
  package let languagesDescription: String
}
