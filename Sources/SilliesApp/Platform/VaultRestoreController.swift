import AppKit
import SilliesVault

@MainActor final class VaultRestoreController {
  private let library: VaultLibrary
  private let chooser = NativeFileDialog()
  private var task: Task<Void, Never>?
  init(library: VaultLibrary) { self.library = library }
  func chooseBackup(parent: NSWindow, completion: @escaping (String?) -> Void) {
    guard !chooser.isPresented, task == nil else {
      completion(nil)
      return
    }
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = String(localized: "Prepare restore")
    panel.message = String(
      localized:
        "Choose a Sillies Vault backup. On the next launch, it will replace the Vault. Your current Vault will be preserved in a separate recovery folder. Conversations and downloaded models stay as they are."
    )
    chooser.choose(panel, for: parent) { [weak self] source in
      guard let self, let source else {
        completion(nil)
        return
      }
      task = Task { [weak self, library] in
        defer { self?.task = nil }
        do {
          try await library.prepareRestore(from: source)
          completion(
            String(
              localized:
                "Backup ready. Quit and reopen Sillies to restore it, or cancel the restore below.")
          )
        } catch is CancellationError { completion(nil) } catch {
          fputs("Vault restore preparation failed: \(error)\n", stderr)
          completion(error.localizedDescription)
        }
      }
    }
  }
  @discardableResult func stop() -> Task<Void, Never>? {
    let pending = task
    chooser.cancel()
    pending?.cancel()
    return pending
  }
  isolated deinit { stop() }
}
