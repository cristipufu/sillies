import SilliesCore
import SilliesVault

/// Native presentation stays with the persistent Vault window, not its browsing model.
@MainActor struct VaultWindowActions {
  let export: (VaultExportSelection, @escaping (String?) -> Void) -> Void
  let popOutTranscript: (SessionRecord) -> Void
  var backup: ((@escaping (String?) -> Void) -> Void)?
  var relink: ((VaultFileReference, @escaping (String?) -> Void) -> Void)?
  var exportText: ((String, @escaping (String?) -> Void) -> Void)?
  var prepareRestore: ((@escaping (String?) -> Void) -> Void)?
  var cancelFileOperation: (@MainActor (@escaping @MainActor () -> Void) -> Void)?
}
