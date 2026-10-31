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
  private weak var companions: (any WritingCompanionHost)?
  private let services: WritingServices
  private var isSuspended = false
  private var hasVisibleAnchor = false
  private let speech: SpeechServices
  var modelID: String { speech.models.selectedModelID }

  init(
    speech: SpeechServices, companions: any WritingCompanionHost, services: WritingServices,
    preferences: DictationPreferences = .init()
  ) {
    self.companions = companions
    self.services = services
    self.speech = speech
    vocabulary = speech.vocabulary
    languages = speech.languages
    stash = StashPickerController(vault: services.vault)
    let historyDirectory = services.vault.storageDirectory.deletingLastPathComponent()
      .appendingPathComponent("Dictation", isDirectory: true)
    let history = WritingHistory(directory: historyDirectory)
    let cleanup = BoundedTextCleanup()
    selection = SelectionCommandCoordinator(history: history, services: .init(cleanup: cleanup))
    dictation = DictationCoordinator(
      services: .init(
        factory: speech.captureFactory, languages: speech.languages, cleanup: cleanup),
      preferences: preferences, history: history,
      vocabulary: speech.vocabulary)
    connectSessions()
    connectCommands()
    companions.onOpenWritingSession = { [weak self] in self?.openSessionOrHistory() }
    companions.onWritingAnchorChanged = { [weak self] in self?.attach(to: $0) }
    preparePanels()
  }

  private func connectSessions() {
    dictation.environment = .init(
      canStart: { [weak recording = services.recording, weak selection] in
        recording?.hasActiveRecording != true && selection?.isWorking != true
      },
      activityChanged: { [weak self] in self?.setActivity($0) },
      changed: { [weak self] in self?.present() })
    selection.activityChanged = { [weak self] in self?.setActivity($0) }
    selection.changed = { [weak self] in self?.presentSelection() }
    services.recording.canStartAudio = { [weak self] in self?.isBusy != true }
  }

  private func connectCommands() {
    services.commands.onWritingCommand = { [weak self] in self?.perform($0) ?? false }
    services.commands.onReleaseDictation = { [weak self] in self?.dictation.releaseHold() }
    services.commands.onStopWriting = { [weak self] in self?.stop() }
  }

  private func preparePanels() {
    panel.prepare(
      dictation, copy: { [weak self] in self?.clipboard.copyText($0) },
      history: { [weak self] in self?.openHistory() })
    selectionPanel.prepare(
      selection, copy: { [weak self] in self?.clipboard.copyText($0) },
      history: { [weak self] in self?.openHistory() })
  }

  private func openSessionOrHistory() {
    guard dictation.phase != .idle else {
      openHistory()
      return
    }
    panel.openSession(
      dictation, copy: { [weak self] in self?.clipboard.copyText($0) },
      history: { [weak self] in self?.openHistory() })
  }

  private func presentSelection() {
    guard !isSuspended else { return }
    selectionPanel.show(
      selection, copy: { [weak self] in self?.clipboard.copyText($0) },
      history: { [weak self] in self?.openHistory() })
    releaseCompanionIfDismissed()
  }

  private func attach(to anchor: WritingCompanionAnchor?) {
    guard let anchor else {
      hasVisibleAnchor = false
      panel.close()
      selectionPanel.close()
      return
    }
    let needsPresentation = !hasVisibleAnchor
    hasVisibleAnchor = true
    panel.attach(to: anchor)
    selectionPanel.attach(to: anchor)
    if needsPresentation {
      present()
      presentSelection()
    }
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
    guard let companions else { return false }
    guard !services.recording.hasActiveRecording else {
      feedback.showMessage(
        "Finish the current recording before writing.", at: NSEvent.mouseLocation)
      return false
    }
    guard companions.hasAvailableWritingCompanion else {
      feedback.showMessage(
        "All companions are busy. Free one to start writing.", at: NSEvent.mouseLocation)
      return false
    }
    dictation.dismiss()
    selection.dismiss()
    panel.close()
    selectionPanel.close()
    guard let anchor = companions.beginWritingIndicator() else { return false }
    hasVisibleAnchor = true
    panel.attach(to: anchor)
    selectionPanel.attach(to: anchor)
    return true
  }

  private func setActivity(_ active: Bool) {
    guard let companions else { return }
    if active {
      services.vault.suspendBackgroundProcessing()
      if let anchor = companions.beginWritingIndicator() {
        panel.attach(to: anchor)
        selectionPanel.attach(to: anchor)
      }
    } else {
      guard !dictation.isActive, !selection.isWorking else { return }
      companions.finishWritingIndicator()
      releaseCompanionIfDismissed()
      if !isSuspended, companions.shouldRun { services.vault.resumeBackgroundProcessing() }
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
    if dictation.phase == .idle, !selection.isPresented { companions?.endWritingIndicator() }
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
    companions?.endWritingIndicator()
    stash.stop()
    pasteBack.release()
    services.vault.suspendBackgroundProcessing()
    speech.releaseInteractiveResources()
  }
}
