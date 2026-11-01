import Foundation

/// Explicit developer diagnostics only. No environment access or reporting in ordinary inference.
package struct FishProfileConfiguration: Sendable {
  package enum Mode: String, Sendable, Codable { case unmeasured, natural, fenced }
  package let directory: URL
  package let mode: Mode
  package let seed: UInt64

  package init(directory: URL, mode: Mode, seed: UInt64) {
    self.directory = directory
    self.mode = mode
    self.seed = seed
  }
}
