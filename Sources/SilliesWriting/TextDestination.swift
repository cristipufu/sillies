import Foundation

package struct TextDestination: Sendable {
  package let id: UUID
  package let application: FrontmostApplication
  package let selection: String
  package var processID: Int32 { application.processID }
  package var applicationName: String { application.name }
  package var bundleIdentifier: String? { application.bundleIdentifier }
  package init(id: UUID, application: FrontmostApplication, selection: String) {
    self.id = id
    self.application = application
    self.selection = selection
  }
}
