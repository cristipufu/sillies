import Foundation
import Observation
import SilliesAudio
import SilliesCore
import SilliesReasoning
import SilliesSpeech

/// Owns an explicit microphone session; the companion only observes its presentation.
@MainActor @Observable
package final class DictationCoordinator {
  package enum Phase { case idle, preparing, listening, finalizing, delivering, result }
  package enum Mode { case hold, toggle }
  @MainActor package struct Environment {
    package var canStart: () -> Bool = { true }
    package var activityChanged: (Bool) -> Void = { _ in }
    package var changed: () -> Void = {}
    package init(
      canStart: @escaping () -> Bool = { true },
      activityChanged: @escaping (Bool) -> Void = { _ in }, changed: @escaping () -> Void = {}
    ) {
      self.canStart = canStart
      self.activityChanged = activityChanged
      self.changed = changed
    }
  }
  @MainActor package struct Services {
    package let capture: WritingCaptureServices
    package let text: WritingTextServices
    package let context: WritingContext
    package init(
      capture: WritingCaptureServices, text: WritingTextServices, context: WritingContext
    ) {
      self.capture = capture
      self.text = text
      self.context = context
    }
  }
  private enum Limits {
    static let cleanupDeadline: Duration = .milliseconds(750)
    static let maximumCapture: Duration = .seconds(300)
  }
  private let preferences: any WritingPreferencesReading
  private let history: any WritingHistoryRecording
  private let captureServices: WritingCaptureServices
  private let textServices: WritingTextServices
  private let context: WritingContext
  private var run: DictationRun?
  private var startFailure: String?
  private var stoppingRun: DictationRun?
  @ObservationIgnored private var stopCompletions: [@MainActor @Sendable () -> Void] = []
  package var environment = Environment()
  package var phase: Phase { startFailure == nil ? (run?.phase ?? .idle) : .result }
  package var status: String { startFailure ?? run?.status ?? "Ready to dictate" }
  package var preview: String { run?.preview ?? "" }
  package var level: Double { run?.level ?? 0 }
  package var elapsed: TimeInterval { run?.elapsed ?? 0 }
  package var insertionFailure: SessionFailure? { run?.insertionFailure }
  package var captureFailure: SessionFailure? { run?.captureFailure }
  package var recoveryFailure: SessionFailure? { captureFailure ?? insertionFailure }
  package var historyFailure: WritingHistoryFailure? { history.persistence.failure }
  package var canInsert: Bool { run?.canInsert == true }
  package var followsLiveTranscript: Bool {
    get { run?.followsLiveTranscript ?? true }
    set { run?.followsLiveTranscript = newValue }
  }
  package var result: WritingResult? { run?.result }
  package var releaseToInsertion: TimeInterval? { run?.releaseToInsertion }
  package var applicationName: String { run?.application.name ?? "the original app" }
  package var isActive: Bool { run?.isActive == true }
  package var isBusy: Bool { isActive || stoppingRun != nil }
  package var canFinish: Bool { phase == .listening }
  package var hudStatus: String {
    guard phase == .listening else { return status }
    let instruction = run?.mode == .hold ? "Release to finish" : "Press again to finish"
    return "\(SessionRecord.formatDuration(elapsed)) · \(instruction)"
  }

  package init(
    services: Services, preferences: any WritingPreferencesReading,
    history: any WritingHistoryRecording
  ) {
    captureServices = services.capture
    textServices = services.text
    context = services.context
    self.preferences = preferences
    self.history = history
  }
  package func retryHistory() { history.retry() }
  package func toggle() {
    if phase == .listening {
      finish()
    } else if phase == .preparing {
      cancel()
    } else if !isBusy {
      start(.toggle)
    }
  }
  package func releaseHold() {
    guard run?.mode == .hold else { return }
    if phase == .preparing {
      cancel()
      run?.show("Released before the microphone was ready. Try toggle dictation.")
      environment.changed()
    } else if phase == .listening {
      finish()
    }
  }
  package func start(_ mode: Mode) {
    guard !isBusy else { return }
    startFailure = nil
    guard environment.canStart() else {
      showStartFailure("Finish the current recording before dictating.")
      return
    }
    guard let application = context.currentApplication() else {
      showStartFailure("Focus the text field you want to write in first.")
      return
    }
    let next = DictationRun(
      application: application, mode: mode,
      options: .init(
        style: preferences.style, languageIdentifier: preferences.languageIdentifier,
        vocabulary: context.vocabularyHints()))
    run = next
    environment.activityChanged(true)
    environment.changed()
    next.operation = Task { [weak self] in await self?.prepare(next) }
  }
  private func showStartFailure(_ message: String) {
    run = nil
    startFailure = message
    environment.changed()
  }
  private func owns(_ candidate: DictationRun) -> Bool { run === candidate && candidate.isValid }
  private func accepts(_ candidate: DictationRun) -> Bool { owns(candidate) && !Task.isCancelled }

  private func prepare(_ run: DictationRun) async {
    do {
      try await captureDestination(for: run)
      guard accepts(run) else { return }
      let catalog = try await captureServices.loadLanguages()
      guard accepts(run) else { return }
      let identifier = run.options.languageIdentifier
      let language =
        identifier == "auto"
        ? catalog.preferredLanguage(savedIdentifier: identifier)
        : catalog.installedLanguage(matching: identifier)
      guard let language else {
        run.show(
          "Choose an installed dictation language in Settings. English and Romanian require a model that supports them."
        )
        endActivity(run)
        environment.changed()
        return
      }
      beginCapture(run, language: language, model: catalog.model)
    } catch {
      guard accepts(run) else { return }
      run.show(error.localizedDescription)
      endActivity(run)
      environment.changed()
    }
  }
  private func captureDestination(for run: DictationRun) async throws {
    do {
      let destination = try await textServices.insertion.capture(run.application)
      guard accepts(run) else {
        await textServices.insertion.release(destination)
        throw CancellationError()
      }
      run.accept(destination)
    } catch {
      guard accepts(run) else { throw CancellationError() }
      if case TextAccessError.protectedField = error { throw error }
      if error is CancellationError { throw error }
      run.denyInsertion(error)
      environment.changed()
    }
  }
  private func beginCapture(
    _ run: DictationRun, language: SpeechLanguage, model: SpeechModelDescriptor
  ) {
    guard owns(run), run.phase == .preparing else { return }
    var config = AudioCaptureConfiguration(
      kind: .record, target: nil, recordingURL: nil, language: language)
    config.model = model
    config.recognitionContext.priority = .interactive
    let updates = AudioSessionUpdateDelivery(schedule: captureServices.deliver) {
      [weak self, weak run] update in
      guard let run else { return }
      self?.receive(update, for: run)
    }
    let capture = captureServices.factory(config) { updates.enqueue($0) }
    run.attach(capture, updates: updates)
    capture.start()
    run.deadline = Task { [weak self, weak run] in
      do { try await Task.sleep(for: Limits.maximumCapture) } catch { return }
      guard let self, let run, self.accepts(run) else { return }
      if run.phase == .listening { self.finish() } else { self.cancel() }
    }
  }
  private func receive(_ update: AudioCaptureUpdate, for run: DictationRun) {
    guard owns(run), run.phase == .preparing || run.phase == .listening else { return }
    switch update {
    case .preparing(let message): run.preparing(message)
    case .capturing: run.listening()
    case .transcript(let text, let level, let elapsed):
      run.progress(text: text, level: level, elapsed: elapsed)
    case .failed(let failure), .transcriptionStopped(let failure):
      run.failCapture(failure)
      finish()
    default: break
    }
    environment.changed()
  }
  package func finish() {
    guard let run, owns(run), run.phase == .listening || run.phase == .preparing else { return }
    guard run.hasCapture else {
      cancel()
      return
    }
    run.finalize(at: ProcessInfo.processInfo.systemUptime)
    environment.changed()
    stopCapture(run) { [weak self] in
      guard let self, self.owns(run) else { return }
      run.operation = Task { await self.deliver(run) }
    }
  }
  private func deliver(_ run: DictationRun) async {
    guard accepts(run), let captured = run.takeFinalized() else { return }
    let raw = captured.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else {
      run.show(captured.failure?.message ?? "No speech was recognized.")
      endActivity(run)
      environment.changed()
      return
    }
    var completed = WritingResult(
      originalText: raw, text: raw, applicationName: run.application.name)
    history.save(completed)
    run.delivering()
    environment.changed()
    completed = await cleaned(completed, for: run)
    guard accepts(run) else { return }
    let insertedAt = await insert(&completed, captured: captured, run: run)
    history.save(completed)
    guard accepts(run) else { return }
    run.complete(completed, insertedAt: insertedAt)
    endActivity(run)
    environment.changed()
  }
  private func cleaned(_ result: WritingResult, for run: DictationRun) async -> WritingResult {
    guard run.options.style == .lightlyCleaned else { return result }
    let hints = run.options.vocabulary
    let text = await textServices.cleanup.process(
      result.originalText, deadline: Limits.cleanupDeadline
    ) { [textServices] source in
      let output = try await textServices.transform(source, .cleanup)
      return TextCleanupGuard.accepts(output, source: source, vocabulary: hints) ? output : source
    }
    var result = result
    result.text = text ?? result.originalText
    if text == nil {
      result.notice = "Used the transcript: cleanup was unavailable or missed its deadline."
    }
    return result
  }
  private func insert(
    _ result: inout WritingResult, captured: AudioCaptureResult, run: DictationRun
  ) async -> TimeInterval? {
    guard let destination = run.destination, captured.failure == nil, run.insertionNotice.isEmpty
    else {
      result.delivery = .needsPaste
      result.notice = captured.failure?.message ?? run.insertionNotice
      return nil
    }
    do {
      try await textServices.insertion.insert(result.text, into: destination)
      result.delivery = .inserted
      return ProcessInfo.processInfo.systemUptime
    } catch {
      result.delivery = .needsPaste
      result.notice = error.localizedDescription
      return nil
    }
  }
  package func cancel() {
    startFailure = nil
    guard let run else {
      environment.changed()
      return
    }
    run.cancel()
    stopCapture(run) {}
    endActivity(run)
    environment.changed()
  }
  package func dismiss() {
    startFailure = nil
    if isActive { cancel() }
    run?.dismiss()
    environment.changed()
  }
  package func suspend() {
    startFailure = nil
    guard let run else { return }
    run.suspend()
    preserveInterrupted(run)
    stopCapture(run) {}
    endActivity(run)
  }
  package func flushForTermination(_ completion: @escaping @MainActor @Sendable () -> Void) {
    suspend()
    let flush: @MainActor @Sendable () -> Void = { [history] in history.flush { _ in completion() }
    }
    if stoppingRun == nil { flush() } else { stopCompletions.append(flush) }
  }
  private func stopCapture(
    _ run: DictationRun, completion: @escaping @MainActor () -> Void
  ) {
    guard let capture = run.takeCapture() else { return }
    stoppingRun = run
    capture.finish { [weak self, schedule = captureServices.deliver] captured in
      schedule {
        guard let self, self.stoppingRun === run else { return }
        self.stoppingRun = nil
        if run.disposition != .discard { run.stageFinalized(captured) }
        if run.disposition == .recover {
          self.preserveInterrupted(run)
        } else if run.disposition == .deliver {
          completion()
        }
        let completions = self.stopCompletions
        self.stopCompletions.removeAll()
        for complete in completions { complete() }
      }
    }
  }
  private func preserveInterrupted(_ run: DictationRun) {
    guard let captured = run.takeFinalized() else { return }
    let text = captured.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    var result = WritingResult(
      originalText: text, text: text, applicationName: run.application.name,
      notice: "Dictation stopped before insertion. Your transcript is ready to copy.")
    result.delivery = .needsPaste
    history.save(result)
    run.preserve(result)
  }
  private func endActivity(_ run: DictationRun) {
    if let destination = run.takeDestination() {
      Task { [insertion = textServices.insertion] in await insertion.release(destination) }
    }
    if self.run === run { environment.activityChanged(false) }
  }
}
