import AppKit
import SilliesCore
import SilliesVault

@MainActor final class VaultFileReferenceController {
  private let library: VaultLibrary
  private let chooser = NativeFileDialog()
  private var task: Task<Void, Never>?
  init(library: VaultLibrary) { self.library = library }
  func relink(
    _ reference: VaultFileReference, parent: NSWindow, completion: @escaping (String?) -> Void
  ) {
    guard !chooser.isPresented, task == nil else {
      completion(nil)
      return
    }
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = String(localized: "Relink")
    panel.message = String(
      localized:
        "Choose the file's current location. Sillies keeps a reference; it does not copy or move the file."
    )
    chooser.choose(panel, for: parent) { [weak self] url in
      guard let self, let url else {
        completion(nil)
        return
      }
      task = Task { [weak self, library] in
        defer { self?.task = nil }
        do {
          try Task.checkCancellation()
          try await library.relink(reference, to: url)
          guard !Task.isCancelled else {
            completion(nil)
            return
          }
          completion(String(localized: "File reference updated"))
        } catch is CancellationError { completion(nil) } catch {
          fputs("Vault file relink failed: \(error)\n", stderr)
          completion(error.localizedDescription)
        }
      }
    }
  }
  func stop() {
    chooser.cancel()
    task?.cancel()
  }
  isolated deinit { stop() }
}
