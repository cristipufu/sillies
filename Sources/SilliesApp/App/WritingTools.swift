import AppKit
import SilliesCore
import SwiftUI

/// Composition of interactive writing; neither the window tracker nor mascot owns capture.
@MainActor final class WritingTools {
  let dictation: DictationCoordinator
  let selection: SelectionCommandCoordinator
  let vocabulary: VocabularyPreferences
  let languages: AudioLanguageEnvironment
  let pasteBack = PasteBackCoordinator()
  private let stash: StashPickerController
  private let panel = DictationPanelController()
  private let selectionPanel = SelectionCommandPanel()
  private let clipboard = VaultClipboard(
    pasteboard: .general, queue: .init(label: "app.sillies.writing-clipboard"))
  private var historyWindow: NSWindow?
  private weak var controller: CompanionController?
  private var isSuspended = false
  private let speech: SpeechServices
  var modelID: String { speech.models.selectedModelID }

  init(speech: SpeechServices, controller: CompanionController) {
    self.controller = controller
    self.speech = speech
    vocabulary = speech.vocabulary
    languages = speech.languages
    stash = StashPickerController(vault: controller.skills.vault)
    let historyDirectory = controller.skills.vault.storageDirectory.deletingLastPathComponent()
      .appendingPathComponent("Dictation", isDirectory: true)
    let history = WritingHistory(directory: historyDirectory)
    let cleanup = BoundedTextCleanup()
    selection = SelectionCommandCoordinator(history: history, services: .init(cleanup: cleanup))
    dictation = DictationCoordinator(
      services: .init(
        factory: speech.captureFactory, languages: speech.languages, cleanup: cleanup),
      preferences: DictationPreferences(), history: history,
      vocabulary: speech.vocabulary)
    dictation.environment = .init(
      canStart: { [weak controller, weak selection] in
        controller?.skills.activeAudioSession == nil && selection?.isWorking != true
      },
      activityChanged: { [weak self] in self?.setActivity($0) },
      changed: { [weak self] in self?.present() })
    selection.activityChanged = { [weak self] in self?.setActivity($0) }
    selection.changed = { [weak self] in
      guard let self else { return }
      self.selectionPanel.show(self.selection) { [weak self] in self?.clipboard.copyText($0) }
    }
    controller.commands.onWritingCommand = { [weak self] in self?.perform($0) ?? false }
    controller.commands.onReleaseDictation = { [weak self] in self?.dictation.releaseHold() }
    controller.commands.onStopWriting = { [weak self] in self?.stop() }
    controller.onWritingAnchorChanged = { [weak self] point in
      self?.panel.move(to: point)
      self?.selectionPanel.move(to: point)
    }
    controller.skills.canStartAudio = { [weak self] in self?.isBusy != true }
    panel.prepare(
      dictation, copy: { [weak self] in self?.clipboard.copyText($0) },
      history: { [weak self] in self?.openHistory() })
    selectionPanel.prepare(selection) { [weak self] in self?.clipboard.copyText($0) }
  }
  private var isBusy: Bool { dictation.isBusy || selection.isWorking }
  func enableInsertionAccess() {
    controller?.tracker.requestAccessibility()
    if controller?.tracker.hasAccessibility != true {
      controller?.tracker.openAccessibilitySettings()
    }
  }

  private func perform(_ command: AppCommand) -> Bool {
    isSuspended = false
    switch command {
    case .holdDictation: dictation.start(.hold)
    case .toggleDictation: dictation.toggle()
    case .cancelDictation:
      dictation.cancel()
      selection.cancel()
      selectionPanel.close()
    case .dictationHistory: openHistory()
    case .searchStash: if !isBusy { stash.show() }
    case .shortenSelection: if !isBusy { selection.start(.shorten) }
    case .fixSelectionGrammar: if !isBusy { selection.start(.grammar) }
    case .translateSelection:
      if !isBusy { selection.start(.translate(dictation.preferences.translationLanguage)) }
    default: return false
    }
    return true
  }

  private func setActivity(_ active: Bool) {
    guard let controller else { return }
    if active {
      controller.skills.vault.suspendBackgroundProcessing()
      let anchor = controller.beginWritingIndicator()
      panel.move(to: anchor)
      selectionPanel.move(to: anchor)
    } else {
      guard !dictation.isActive, !selection.isWorking else { return }
      controller.endWritingIndicator()
      if !isSuspended, controller.shouldRun { controller.skills.vault.resumeBackgroundProcessing() }
    }
  }
  private func present() {
    guard !isSuspended else { return }
    panel.show(
      dictation, copy: { [weak self] in self?.clipboard.copyText($0) },
      history: { [weak self] in self?.openHistory() })
  }
  func openHistory() {
    if historyWindow == nil {
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 590, height: 510),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      window.title = "Sillies · Writing recovery"
      window.isReleasedWhenClosed = false
      window.contentViewController = NSHostingController(
        rootView: WritingHistoryView(model: dictation.history) { [weak self] in
          self?.clipboard.copyText($0)
        })
      window.center()
      historyWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    historyWindow?.makeKeyAndOrderFront(nil)
  }
  func stop() {
    isSuspended = true
    dictation.suspend()
    selection.cancel()
    panel.close()
    selectionPanel.close()
    stash.stop()
    pasteBack.release()
    controller?.skills.vault.suspendBackgroundProcessing()
    speech.releaseInteractiveResources()
  }
}
