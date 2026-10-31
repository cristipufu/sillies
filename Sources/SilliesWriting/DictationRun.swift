import Foundation
import Observation
import SilliesAudio
import SilliesCore

/// State and resources belonging to exactly one dictation attempt.
@MainActor @Observable final class DictationRun {
  struct Options {
    let style: DictationOutputStyle
    let languageIdentifier: String
    let vocabulary: [String]
  }
  enum CaptureDisposition { case deliver, discard, recover }
  let application: FrontmostApplication
  let mode: DictationCoordinator.Mode
  let options: Options
  private(set) var phase = DictationCoordinator.Phase.preparing
  private(set) var status = "Preparing microphone…"
  private(set) var preview = ""
  private(set) var level = 0.0
  private(set) var elapsed: TimeInterval = 0
  private(set) var insertionFailure: SessionFailure?
  private(set) var captureFailure: SessionFailure?
  private(set) var insertionNotice = ""
  private(set) var destination: TextDestination?
  private(set) var result: WritingResult?
  private(set) var releaseToInsertion: TimeInterval?
  private(set) var releasedAt: TimeInterval?
  private(set) var isValid = true
  private(set) var disposition = CaptureDisposition.deliver
  var followsLiveTranscript = true
  @ObservationIgnored var operation: Task<Void, Never>?
  @ObservationIgnored var deadline: Task<Void, Never>?
  @ObservationIgnored private var finalized: AudioCaptureResult?
  @ObservationIgnored private var capture: (any SessionAudioCapture)?
  @ObservationIgnored private var updates: AudioSessionUpdateDelivery?
  var hasCapture: Bool { capture != nil }
  var canInsert: Bool { destination != nil && insertionNotice.isEmpty }
  var isActive: Bool { [.preparing, .listening, .finalizing, .delivering].contains(phase) }

  init(application: FrontmostApplication, mode: DictationCoordinator.Mode, options: Options) {
    self.application = application
    self.mode = mode
    self.options = options
  }
  func accept(_ destination: TextDestination) { self.destination = destination }
  func denyInsertion(_ error: Error) {
    insertionNotice = error.localizedDescription
    if case TextAccessError.permission = error {
      insertionFailure = .permissionDenied(.openAccessibilitySettings)
    }
  }
  func attach(_ capture: any SessionAudioCapture, updates: AudioSessionUpdateDelivery) {
    self.capture = capture
    self.updates = updates
  }
  func stageFinalized(_ result: AudioCaptureResult) { finalized = result }
  func takeFinalized() -> AudioCaptureResult? {
    defer { finalized = nil }
    return finalized
  }
  func takeCapture() -> (any SessionAudioCapture)? {
    defer { capture = nil }
    return capture
  }
  func takeDestination() -> TextDestination? {
    defer { destination = nil }
    return destination
  }
  func preparing(_ message: String) { status = message }
  func listening() {
    phase = .listening
    status = mode == .hold ? "Listening · release to insert" : "Listening · press again to finish"
    if destination == nil { status += " · copy only" }
  }
  func progress(text: String, level: Double, elapsed: TimeInterval) {
    preview = text
    self.level = level
    self.elapsed = elapsed
  }
  func failCapture(_ failure: SessionFailure) {
    captureFailure = failure
    insertionNotice = failure.message
  }
  func finalize(at time: TimeInterval) {
    releasedAt = time
    phase = .finalizing
    status = "Finishing speech…"
    level = 0
    stopUpdates()
  }
  func delivering() {
    phase = .delivering
    status = "Preparing your text…"
  }
  func complete(_ result: WritingResult, insertedAt: TimeInterval?) {
    self.result = result
    preview = result.text
    if let insertedAt, let releasedAt { releaseToInsertion = insertedAt - releasedAt }
    show(
      result.delivery == .inserted
        ? "Inserted into \(application.name)" : "Your text is ready to copy")
  }
  func show(_ message: String) {
    status = message
    phase = .result
  }
  func dismiss() { phase = .idle }
  func cancel() {
    finalized = nil
    disposition = .discard
    invalidate()
    status = "Dictation canceled"
  }
  func suspend() {
    if disposition != .discard { disposition = .recover }
    invalidate()
  }
  func preserve(_ result: WritingResult) { self.result = result }
  private func invalidate() {
    isValid = false
    operation?.cancel()
    operation = nil
    stopUpdates()
    phase = .idle
  }
  private func stopUpdates() {
    updates?.stop()
    updates = nil
    deadline?.cancel()
    deadline = nil
  }
}
