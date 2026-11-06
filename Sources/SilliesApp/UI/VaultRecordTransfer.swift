import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Only the identity crosses the drag boundary. The recipient re-reads the local Vault.
struct VaultRecordTransfer: Codable, Transferable {
  let id: UUID
  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .silliesVaultRecord)
  }
}

extension UTType {
  static let silliesVaultRecord = UTType(
    exportedAs: "app.sillies.vault-record", conformingTo: .data)
}
