import SilliesCore
import SilliesVault

/// Native presentation stays with the persistent Vault window, not its browsing model.
@MainActor struct VaultWindowActions {
  let export: (VaultExportSelection, @escaping (String?) -> Void) -> Void
  let popOutTranscript: (SessionRecord) -> Void
}
