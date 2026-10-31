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
  private let feedback = StashFeedbackController()
  private let clipboard = VaultClipboard(
    pasteboard: .general, queue: .init(label: "app.sillies.writing-clipboard"))
  private var historyWindow: NSWindow?
  private let recoveredText = SavedTranscriptWindow()
  private weak var controller: CompanionController?
  private var isSuspended = false
  private var hasVisibleAnchor = false
  private let speech: SpeechServices
  var modelID: String { speech.models.selectedModelID }

  init(
    speech: SpeechServices, controller: CompanionController,
    preferences: DictationPreferences = .init()
  ) {
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
      preferences: preferences, history: history,
      vocabulary: speech.vocabulary)
    dictation.environment = .init(
      canStart: { [weak controller, weak selection] in
        controller?.skills.activeAudioSession == nil && selection?.isWorking != true
      },
      activityChanged: { [weak self] in self?.setActivity($0) },
      changed: { [weak self] in self?.present() })
    selection.activityChanged = { [weak self] in self?.setActivity($0) }
    selection.changed = { [weak self] in
      guard let self, !self.isSuspended else { return }
      self.selectionPanel.show(
        self.selection, copy: { [weak self] in self?.clipboard.copyText($0) },
        history: { [weak self] in self?.openHistory() })
      self.releaseCompanionIfDismissed()
    }
    controller.commands.onWritingCommand = { [weak self] in self?.perform($0) ?? false }
    controller.commands.onReleaseDictation = { [weak self] in self?.dictation.releaseHold() }
    controller.commands.onStopWriting = { [weak self] in self?.stop() }
    controller.onOpenWritingSession = { [weak self] in
      guard let self else { return }
      if self.dictation.phase != .idle {
        self.panel.openSession(
          self.dictation, copy: { [weak self] in self?.clipboard.copyText($0) },
          history: { [weak self] in self?.openHistory() })
      } else {
        self.openHistory()
      }
    }
    controller.onWritingAnchorChanged = { [weak self] anchor in
      guard let self else { return }
      guard let anchor else {
        self.hasVisibleAnchor = false
        self.panel.close()
        self.selectionPanel.close()
        return
      }
      let needsPresentation = !self.hasVisibleAnchor
      self.hasVisibleAnchor = true
      self.panel.attach(to: anchor)
      self.selectionPanel.attach(to: anchor)
      if needsPresentation {
        self.present()
        self.selectionPanel.show(
          self.selection, copy: { [weak self] in self?.clipboard.copyText($0) },
          history: { [weak self] in self?.openHistory() })
      }
    }
    controller.skills.canStartAudio = { [weak self] in self?.isBusy != true }
    panel.prepare(
      dictation, copy: { [weak self] in self?.clipboard.copyText($0) },
      history: { [weak self] in self?.openHistory() })
    selectionPanel.prepare(
      selection, copy: { [weak self] in self?.clipboard.copyText($0) },
      history: { [weak self] in self?.openHistory() })
  }
  private var isBusy: Bool { dictation.isBusy || selection.isWorking }
  func enableInsertionAccess() {
    SessionRecovery.open(.openAccessibilitySettings)
  }

  private func perform(_ command: AppCommand) -> Bool {
    isSuspended = false
    if command.startsWriting, !isBusy, !prepareCompanion() { return true }
    switch command {
    case .holdDictation: dictation.start(.hold)
    case .toggleDictation: dictation.toggle()
    case .cancelDictation:
      dictation.cancel()
      selection.dismiss()
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

  private func prepareCompanion() -> Bool {
    guard let controller else { return false }
    guard controller.skills.activeAudioSession == nil else {
      feedback.showMessage(
        "Finish the current recording before writing.", at: NSEvent.mouseLocation)
      return false
    }
    guard controller.hasAvailableWritingCompanion else {
      feedback.showMessage(
        "All companions are busy. Free one to start writing.", at: NSEvent.mouseLocation)
      return false
    }
    dictation.dismiss()
    selection.dismiss()
    panel.close()
    selectionPanel.close()
    guard let anchor = controller.beginWritingIndicator() else { return false }
    hasVisibleAnchor = true
    panel.attach(to: anchor)
    selectionPanel.attach(to: anchor)
    return true
  }

  private func setActivity(_ active: Bool) {
    guard let controller else { return }
    if active {
      controller.skills.vault.suspendBackgroundProcessing()
      if let anchor = controller.beginWritingIndicator() {
        panel.attach(to: anchor)
        selectionPanel.attach(to: anchor)
      }
    } else {
      guard !dictation.isActive, !selection.isWorking else { return }
      controller.finishWritingIndicator()
      releaseCompanionIfDismissed()
      if !isSuspended, controller.shouldRun { controller.skills.vault.resumeBackgroundProcessing() }
    }
  }
  private func present() {
    guard !isSuspended else { return }
    panel.show(
      dictation, copy: { [weak self] in self?.clipboard.copyText($0) },
      history: { [weak self] in self?.openHistory() })
    releaseCompanionIfDismissed()
  }
  private func releaseCompanionIfDismissed() {
    if dictation.phase == .idle, !selection.isPresented { controller?.endWritingIndicator() }
  }
  func openHistory() {
    if historyWindow == nil {
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 640, height: 560),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      window.title = "Sillies · Recent writing"
      AppContentWindowStacking.shared.register(window)
      window.isReleasedWhenClosed = false
      window.contentMinSize = CGSize(width: 560, height: 400)
      window.contentViewController = NSHostingController(
        rootView: WritingHistoryView(
          model: dictation.history,
          copy: { [weak self] in self?.clipboard.copyText($0) },
          openText: { [weak self] result in
            self?.recoveredText.show(
              result.text, title: "Sillies · \(result.applicationName) · Recent writing")
          }))
      window.center()
      historyWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    historyWindow?.makeKeyAndOrderFront(nil)
  }
  func stop() {
    isSuspended = true
    hasVisibleAnchor = false
    dictation.suspend()
    selection.dismiss()
    panel.close()
    selectionPanel.close()
    feedback.close()
    controller?.endWritingIndicator()
    stash.stop()
    pasteBack.release()
    controller?.skills.vault.suspendBackgroundProcessing()
    speech.releaseInteractiveResources()
  }
}
