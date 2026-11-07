import Foundation
import SilliesCore
import SilliesPersistence

extension VaultLibrary {
  package func setProtection(_ protection: VaultRecordProtection, for id: UUID) throws
    -> VaultSnapshot?
  {
    guard try storage().setProtection(protection, for: id) else { return nil }
    cache.remove(id)
    searchRevision = UUID()
    scheduleCleanup()
    return try snapshot()
  }
}
