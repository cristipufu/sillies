import Foundation

package enum VaultExportSelection: Sendable {
  case records([UUID])
  case all
}
