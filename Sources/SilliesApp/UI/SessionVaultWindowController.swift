import AppKit
import SilliesCore
import SwiftUI

/// A reusable browsing lifetime. Opening a destination never replaces the hosted root.
@MainActor final class SessionVaultWindowController: NSObject, NSWindowDelegate {
  enum Destination {
    case resume
    case record(UUID)
    case stash, retention
  }
  struct Services {
    var pasteBack: PasteBackCoordinator?
    var conversations: VaultConversationPresentation?
    var discussion: VaultDiscussionPresentation?
  }
  static let initialSize = CGSize(width: 980, height: 660)
  static let minimumSize = CGSize(width: 880, height: 560)
  private let vault: SessionVaultStore
  private let appearance: ThemeEnvironment
  private let services: Services
  private let exporter: VaultExportController
  private let transcript: SavedTranscriptWindow
  let conversations: VaultConversationsModel?
  let navigation = VaultNavigation()
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
        }),
      discussion: services.discussion))

  init(vault: SessionVaultStore, appearance: ThemeEnvironment, services: Services) {
    self.vault = vault
    self.appearance = appearance
    self.services = services
    conversations = services.conversations.map(VaultConversationsModel.init)
    exporter = VaultExportController(library: vault.library)
    transcript = SavedTranscriptWindow(appearance: appearance)
    super.init()
  }

  func prepare(_ destination: Destination = .resume) {
    if window == nil { makeWindow() }
    model.resume()
    switch destination {
    case .resume: break
    case .record(let id):
      navigation.section = .captures
      model.navigate(to: id)
    case .stash:
      navigation.section = .captures
      model.selectedFilter = .stash
      model.searchQuery = ""
    case .retention: navigation.editor = .retention
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
        vault: vault, conversations: conversations, model: model, navigation: navigation),
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
    navigation.editor = nil
    model.stop()
    exporter.cancel()
    conversations?.stop()
  }

  func close() {
    suspend()
    transcript.close()
    window?.close()
    window = nil
  }
}
