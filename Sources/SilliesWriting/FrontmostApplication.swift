import Foundation

/// Snapshot of the user's intended destination. Native discovery belongs to the app adapter.
package struct FrontmostApplication: Sendable, Equatable {
  package let processID: Int32
  package let name: String
  package let bundleIdentifier: String?
  package init(processID: Int32, name: String, bundleIdentifier: String?) {
    self.processID = processID
    self.name = name
    self.bundleIdentifier = bundleIdentifier
  }
}
