import Foundation
import Observation
import SilliesAudio
import SilliesCore
import SilliesSpeech

/// Owns an explicit microphone session; the companion only observes its presentation.
@MainActor @Observable
final class DictationCoordinator {
  enum Phase { case idle, preparing, listening, finalizing, delivering, result }
  enum Mode { case hold, toggle }
  @MainActor struct Environment {
    var currentApplication: () -> FrontmostApplication? = { .current }
    var canStart: () -> Bool = { true }
    var activityChanged: (Bool) -> Void = { _ in }
    var changed: () -> Void = {}
  }
  @MainActor struct Services {
    let factory: SessionAudioCaptureFactory
    let languages: AudioLanguageEnvironment
    var insertion: any TextInserting = TextInsertionService()
    var cleanup = BoundedTextCleanup()
    var transform: BoundedTextCleanup.Transform = {
      try await LocalReasoningService.shared.transform($0, operation: .cleanup)
    }
  }
  private enum Limits {
    static let cleanupDeadline: Duration = .milliseconds(750)
    static let maximumCapture: Duration = .seconds(300)
  }
  let preferences: DictationPreferences
  let history: WritingHistory
  private(set) var phase = Phase.idle
  private(set) var status = "Ready to dictate"
  private(set) var preview = ""
  private(set) var level = 0.0
  private(set) var elapsed: TimeInterval = 0
  private(set) var insertionFailure: SessionFailure?
  private(set) var captureFailure: SessionFailure?
  var recoveryFailure: SessionFailure? { captureFailure ?? insertionFailure }
  var canInsert: Bool { destination != nil && insertionNotice.isEmpty }
  var followsLiveTranscript = true
  private(set) var result: WritingResult?
  private(set) var releaseToInsertion: TimeInterval?
  var isActive: Bool {
    phase == .preparing || phase == .listening || phase == .finalizing || phase == .delivering
  }
  var isBusy: Bool { isActive || pendingStops > 0 }
  var canFinish: Bool { phase == .listening }
  var hudStatus: String {
    guard phase == .listening else { return status }
    let instruction = mode == .hold ? "Release to finish" : "Press again to finish"
    return "\(SessionRecord.formatDuration(elapsed)) · \(instruction)"
  }
  var environment = Environment()
  private let factory: SessionAudioCaptureFactory
  private let languages: AudioLanguageEnvironment
  private let insertion: any TextInserting
  private let cleanup: BoundedTextCleanup
  private let transform: BoundedTextCleanup.Transform
  private let vocabulary: VocabularyPreferences
  private var mode = Mode.toggle
  private var generation = UUID()
  private var service: (any SessionAudioCapture)?
  private var updates: AudioSessionUpdateDelivery?
  private var operation: Task<Void, Never>?
  private var captureDeadline: Task<Void, Never>?
  private var destination: TextDestination?
  private(set) var applicationName = "the original app"
  private var insertionNotice = ""
  private var pendingStops = 0
  private var releasedAt: TimeInterval?
  private var stopCompletions: [@MainActor @Sendable () -> Void] = []
  private enum CaptureDisposition { case deliver, discard, recover }
  private var captureDisposition = CaptureDisposition.deliver

  init(
    services: Services, preferences: DictationPreferences, history: WritingHistory,
    vocabulary: VocabularyPreferences
  ) {
    factory = services.factory
    languages = services.languages
    self.preferences = preferences
    self.history = history
    self.vocabulary = vocabulary
    insertion = services.insertion
    cleanup = services.cleanup
    transform = services.transform
  }

  func toggle() {
    if phase == .listening {
      finish()
    } else if phase == .preparing {
      cancel()
    } else if !isBusy {
      start(.toggle)
    }
  }
  func releaseHold() {
    guard mode == .hold else { return }
    if phase == .preparing {
      cancel()
      show("Released before the microphone was ready. Try toggle dictation.")
    } else if phase == .listening {
      finish()
    }
  }

  func start(_ mode: Mode) {
    guard !isBusy else { return }
    guard environment.canStart() else {
      show("Finish the current recording before dictating.")
      return
    }
    guard let application = environment.currentApplication() else {
      show("Focus the text field you want to write in first.")
      return
    }
    self.mode = mode
    captureDisposition = .deliver
    generation = UUID()
    let token = generation
    applicationName = application.name
    insertionNotice = ""
    insertionFailure = nil
    captureFailure = nil
    result = nil
    preview = ""
    elapsed = 0
    followsLiveTranscript = true
    releaseToInsertion = nil
    releasedAt = nil
    phase = .preparing
    status = "Preparing microphone…"
    environment.activityChanged(true)
    environment.changed()
    operation = Task { [weak self] in await self?.prepare(application, token: token) }
  }

  private func prepare(_ application: FrontmostApplication, token: UUID) async {
    do {
      do {
        let captured = try await insertion.capture(application)
        guard generation == token, !Task.isCancelled else {
          await insertion.release(captured)
          throw CancellationError()
        }
        destination = captured
      } catch TextAccessError.protectedField { throw TextAccessError.protectedField } catch {
        insertionNotice = error.localizedDescription
        if case TextAccessError.permission = error {
          insertionFailure = .permissionDenied(.openAccessibilitySettings)
          environment.changed()
        }
      }
      try Task.checkCancellation()
      let catalog = try await languages.load()
      try Task.checkCancellation()
      guard generation == token else { return }
      let identifier = preferences.languageIdentifier
      let language =
        identifier == "auto"
        ? catalog.preferredLanguage(savedIdentifier: identifier)
        : catalog.installedLanguage(matching: identifier)
      guard let language else {
        show(
          "Choose an installed dictation language in Settings. English and Romanian require a model that supports them."
        )
        endActivity()
        return
      }
      beginCapture(language: language, model: catalog.model)
    } catch {
      guard generation == token, !Task.isCancelled else { return }
      show(error.localizedDescription)
      endActivity()
    }
  }

  private func beginCapture(language: SpeechLanguage, model: SpeechModelDescriptor) {
    var config = AudioCaptureConfiguration(
      kind: .record, target: nil, recordingURL: nil, language: language)
    config.model = model
    config.recognitionContext.priority = .interactive
    let delivery = AudioSessionUpdateDelivery { [weak self] in self?.receive($0) }
    updates = delivery
    let capture = factory(config) { delivery.enqueue($0) }
    service = capture
    capture.start()
    captureDeadline = Task { [weak self] in
      do { try await Task.sleep(for: Limits.maximumCapture) } catch { return }
      guard let self else { return }
      if self.canFinish { self.finish() } else { self.cancel() }
    }
  }

  private func receive(_ update: AudioCaptureUpdate) {
    guard phase == .preparing || phase == .listening else { return }
    switch update {
    case .preparing(let message): status = message
    case .capturing:
      phase = .listening
      status = mode == .hold ? "Listening · release to insert" : "Listening · press again to finish"
      if destination == nil { status += " · copy only" }
    case .transcript(let text, let level, let elapsed):
      preview = text
      self.level = level
      self.elapsed = elapsed
    case .failed(let failure), .transcriptionStopped(let failure):
      captureFailure = failure
      insertionNotice = failure.message
      finish()
    default: break
    }
    environment.changed()
  }

  func finish() {
    guard phase == .listening || phase == .preparing else { return }
    releasedAt = ProcessInfo.processInfo.systemUptime
    phase = .finalizing
    status = "Finishing speech…"
    level = 0
    stopUpdates()
    environment.changed()
    let token = generation
    stopCapture { [weak self] captured in
      guard let self, self.generation == token else { return }
      self.operation = Task { await self.deliver(captured, token: token) }
    }
  }

  private func deliver(_ captured: AudioCaptureResult, token: UUID) async {
    let raw = captured.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else {
      show(captured.failure?.message ?? "No speech was recognized.")
      endActivity()
      return
    }
    var completed = WritingResult(originalText: raw, text: raw, applicationName: applicationName)
    history.save(completed)
    phase = .delivering
    status = "Preparing your text…"
    environment.changed()
    if preferences.style == .lightlyCleaned {
      let hints = vocabulary.snapshot().hints
      let transform = transform
      let cleaned = await cleanup.process(raw, deadline: Limits.cleanupDeadline) { source in
        let output = try await transform(source)
        return TextCleanupGuard.accepts(output, source: source, vocabulary: hints) ? output : source
      }
      completed.text = cleaned ?? raw
      if cleaned == nil {
        completed.notice = "Used the transcript: cleanup was unavailable or missed its deadline."
      }
    }
    guard generation == token, !Task.isCancelled else { return }
    if let destination, captured.failure == nil, insertionNotice.isEmpty {
      do {
        try await insertion.insert(completed.text, into: destination)
        completed.delivery = .inserted
        if let releasedAt { releaseToInsertion = ProcessInfo.processInfo.systemUptime - releasedAt }
      } catch {
        completed.delivery = .needsPaste
        completed.notice = error.localizedDescription
      }
    } else {
      completed.delivery = .needsPaste
      completed.notice = captured.failure?.message ?? insertionNotice
    }
    history.save(completed)
    guard generation == token else { return }
    result = completed
    preview = completed.text
    show(
      completed.delivery == .inserted
        ? "Inserted into \(applicationName)" : "Your text is ready to copy")
    endActivity()
  }

  func cancel() {
    captureDisposition = .discard
    generation = UUID()
    operation?.cancel()
    operation = nil
    stopUpdates()
    stopCapture { _ in }
    phase = .idle
    status = "Dictation canceled"
    endActivity()
    environment.changed()
  }
  func dismiss() {
    if isActive { cancel() }
    phase = .idle
    environment.changed()
  }

  func flushForTermination(_ completion: @escaping @MainActor @Sendable () -> Void) {
    suspend()
    let flush: @MainActor @Sendable () -> Void = { [history] in
      history.flush(completion: completion)
    }
    if pendingStops == 0 { flush() } else { stopCompletions.append(flush) }
  }

  func suspend() {
    if service != nil || (pendingStops > 0 && captureDisposition != .discard) {
      captureDisposition = .recover
    }
    generation = UUID()
    operation?.cancel()
    operation = nil
    stopUpdates()
    stopCapture { _ in }
    phase = .idle
    endActivity()
  }

  private func preserveInterrupted(_ captured: AudioCaptureResult) {
    captureDisposition = .deliver
    let text = captured.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    var saved = WritingResult(
      originalText: text, text: text, applicationName: applicationName,
      notice: "Dictation stopped before insertion. Your transcript is ready to copy.")
    saved.delivery = .needsPaste
    history.save(saved)
    result = saved
  }

  private func stopUpdates() {
    updates?.stop()
    updates = nil
    captureDeadline?.cancel()
    captureDeadline = nil
  }
  private func stopCapture(_ completion: @escaping @MainActor (AudioCaptureResult) -> Void) {
    guard let service else {
      completion(.init(transcript: "", recordingURL: nil, duration: 0, failure: nil))
      return
    }
    self.service = nil
    pendingStops += 1
    service.finish { [weak self] captured in
      MainRunLoopDelivery.perform {
        self?.pendingStops -= 1
        if self?.captureDisposition == .recover {
          self?.preserveInterrupted(captured)
        } else {
          completion(captured)
        }
        if let self, self.pendingStops == 0 {
          let waiting = self.stopCompletions
          self.stopCompletions.removeAll()
          for complete in waiting { complete() }
        }
      }
    }
  }
  private func endActivity() {
    if let destination { Task { [insertion] in await insertion.release(destination) } }
    destination = nil
    environment.activityChanged(false)
  }
  private func show(_ message: String) {
    status = message
    phase = .result
    environment.changed()
  }
}
