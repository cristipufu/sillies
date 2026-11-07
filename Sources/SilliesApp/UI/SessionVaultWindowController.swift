import AppKit
import SilliesCore
import SwiftUI

/// A reusable browsing lifetime. Opening a destination never replaces the hosted root.
@MainActor final class SessionVaultWindowController: NSObject, NSWindowDelegate {
  enum Destination {
    case resume
    case record(UUID)
    case source(VaultSourceReference)
    case stash, retention
  }
  struct Services {
    var pasteBack: PasteBackCoordinator?
    var conversations: VaultConversationPresentation?
    var discussion: VaultDiscussionPresentation?
  }
  static let initialSize = CGSize(width: 1180, height: 760)
  static let minimumSize = CGSize(width: 760, height: 560)
  private let vault: SessionVaultStore
  private let appearance: ThemeEnvironment
  private let services: Services
  private let exporter: VaultExportController
  private let fileReferences: VaultFileReferenceController
  private let restore: VaultRestoreController
  private let transcript: SavedTranscriptWindow
  private var sourceTask: Task<Void, Never>?
  let conversations: VaultConversationsModel?
  private(set) var window: NSWindow?
  private(set) lazy var model = SessionVaultModel(
    vault: vault,
    presentation: .init(
      pasteBack: services.pasteBack,
      windowActions: .init(
        export: { [weak self] selection, completion in
          guard let self, let window = self.window else {
            completion(nil)
            return
          }
          self.exporter.chooseFolder(selection, parent: window, completion: completion)
        },
        popOutTranscript: { [weak self] record in
          self?.transcript.show(record.transcript, title: record.displayTitle, id: record.id)
        },
        backup: { [weak self] completion in
          guard let self, let window = self.window else {
            completion(nil)
            return
          }
          self.exporter.chooseBackup(parent: window, completion: completion)
        },
        relink: { [weak self] reference, completion in
          guard let self, let window = self.window else {
            completion(nil)
            return
          }
          self.fileReferences.relink(reference, parent: window, completion: completion)
        },
        exportText: { [weak self] text, completion in
          guard let self, let window = self.window else {
            completion(nil)
            return
          }
          self.exporter.chooseTextExport(text, parent: window, completion: completion)
        },
        prepareRestore: { [weak self] completion in
          guard let self, let window = self.window else {
            completion(nil)
            return
          }
          self.restore.chooseBackup(parent: window, completion: completion)
        },
        cancelFileOperation: { [weak self] completion in
          guard let self else {
            completion()
            return
          }
          let exporting = self.exporter.cancel()
          let restoring = self.restore.stop()
          Task { @MainActor in
            await exporting?.value
            await restoring?.value
            completion()
          }
        }),
      discussion: services.discussion))

  init(vault: SessionVaultStore, appearance: ThemeEnvironment, services: Services) {
    self.vault = vault
    self.appearance = appearance
    self.services = services
    conversations = services.conversations.map(VaultConversationsModel.init)
    exporter = VaultExportController(library: vault.library)
    fileReferences = VaultFileReferenceController(library: vault.library)
    restore = VaultRestoreController(library: vault.library)
    transcript = SavedTranscriptWindow(appearance: appearance)
    super.init()
  }

  func prepare(_ destination: Destination = .resume) {
    sourceTask?.cancel()
    if window == nil { makeWindow() }
    model.resume()
    switch destination {
    case .resume: break
    case .source(let reference):
      model.workspace.selectScope(.all)
      conversations?.reader.clear()
      sourceTask = Task { [weak self] in
        guard let self else { return }
        await vault.waitUntilLoaded()
        guard !Task.isCancelled else { return }
        await model.workspace.openSource(reference)
      }
    case .record(let id):
      conversations?.reader.clear()
      model.navigate(to: id)
      model.workspace.reveal(id)
    case .stash:
      conversations?.reader.clear()
      model.selectedFilter = .stash
      model.searchQuery = ""
      model.workspace.selectScope(.links)
    case .retention: model.workspace.showStorage()
    }
  }

  private func makeWindow() {
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: Self.initialSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = String(localized: "Sillies · Session Vault")
    AppContentWindowStacking.shared.register(window)
    appearance.register(window)
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.contentMinSize = Self.minimumSize
    window.delegate = self
    let host = ThemedHostingController(
      rootView: SessionVaultView(
        vault: vault, conversations: conversations, model: model),
      appearance: appearance)
    host.sizingOptions = []
    window.contentViewController = host
    window.setContentSize(Self.initialSize)
    window.center()
    self.window = window
  }

  func show(_ destination: Destination = .resume) {
    prepare(destination)
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  func hide() {
    suspend()
    window?.orderOut(nil)
  }

  func windowWillClose(_ notification: Notification) { suspend() }
  func windowDidMiniaturize(_ notification: Notification) { suspend() }
  func windowDidDeminiaturize(_ notification: Notification) { model.resume() }
  private func suspend() {
    sourceTask?.cancel()
    sourceTask = nil
    model.stop()
    exporter.cancel()
    fileReferences.stop()
    restore.stop()
    conversations?.stop()
  }

  func close() {
    suspend()
    transcript.close()
    window?.close()
    window = nil
  }
}
