import Foundation
import SilliesAudio
import SilliesCore
import SilliesSpeech
import SilliesSpeechApple

struct AudioSkillRequest {
  let kind: CompanionSkillKind
  let target: WindowTargetCandidate?
  let recordingDirectory: URL
}

@MainActor
final class AudioSkillSession: ActiveSkillSession {
  private static let suggestionCheckInterval: TimeInterval = 20
  private static let minimumSourceCharacters = 160
  let presentation: AudioSessionPresentation
  private let request: AudioSkillRequest
  private let captureFactory: SessionAudioCaptureFactory
  private let languages: AudioLanguageEnvironment
  private let onChange: () -> Void
  private let recordID = UUID()
  private var service: (any SessionAudioCapture)?
  private var updateDelivery: AudioSessionUpdateDelivery?
  private var suggestionTask: Task<Void, Never>?
  private var availabilityTask: Task<Void, Never>?
  private var languageTask: Task<Void, Never>?
  private var suggestionGate = MeetingSuggestionGate()
  private var lastSuggestionCheck: TimeInterval = 0
  private var lastSuggestionSource = ""

  init(
    request: AudioSkillRequest,
    captureFactory: @escaping SessionAudioCaptureFactory = {
      AudioTranscriptionService(
        configuration: $0, speech: AppleSpeechProvider.makeChannel, onUpdate: $1)
    }, languages: AudioLanguageEnvironment = .live, onChange: @escaping () -> Void
  ) {
    self.captureFactory = captureFactory
    self.languages = languages
    self.request = request
    self.onChange = onChange
    let source =
      request.kind == .record
      ? "Microphone"
      : "\(request.target?.appName ?? "Application") + microphone"
    presentation = AudioSessionPresentation(kind: request.kind, sourceLabel: source)
    presentation.onPause = { [weak self] in self?.pause() }
    presentation.onResume = { [weak self] in self?.resume() }
    presentation.onSelectLanguage = { [weak self] in self?.selectLanguage($0) }
  }

  var initialStatusDetail: String { presentation.status }

  func start() {
    let load = languages.load
    languageTask = Task { [weak self] in
      let catalog: SpeechLanguageCatalog
      do { catalog = try await load() } catch {
        guard !Task.isCancelled, let self else { return }
        self.presentation.isLoadingLanguages = false
        self.presentation.phase = .failed(SessionFailure(error, category: .transcription))
        self.presentation.status = "Transcription model unavailable · Open Settings"
        self.onChange()
        return
      }
      guard !Task.isCancelled, let self, self.presentation.canFinish else { return }
      self.presentation.model = catalog.model
      self.presentation.diarizationModel = catalog.diarizationModel
      self.presentation.languages = catalog.languages
      self.presentation.isLoadingLanguages = false
      if let selected = catalog.preferredLanguage(
        savedIdentifier: self.languages.preferences.selectedIdentifier(for: catalog.model))
      {
        self.beginCapture(language: selected)
      } else {
        self.presentation.status =
          catalog.installed.isEmpty
          ? "No speech model · Open details" : "Choose language · Open details"
        self.onChange()
      }
    }
  }

  private func beginCapture(language: SpeechLanguage) {
    presentation.selectedLanguageID = language.id
    presentation.status = "Preparing \(language.name)…"
    let url = request.recordingDirectory.appendingPathComponent("\(recordID.uuidString).m4a")
    var configuration = AudioCaptureConfiguration(
      kind: request.kind, target: request.target, recordingURL: url, language: language)
    configuration.model = presentation.model
    configuration.diarizationModel = presentation.diarizationModel
    let delivery = AudioSessionUpdateDelivery { [weak self] in self?.apply($0) }
    updateDelivery = delivery
    let service = captureFactory(configuration) { delivery.enqueue($0) }
    self.service = service
    service.start()
    refreshReasoningAvailability(language)
    onChange()
  }

  private func selectLanguage(_ identifier: String) {
    guard presentation.canSelectLanguage, identifier != presentation.selectedLanguageID,
      let language = presentation.languages.first(where: { $0.id == identifier && $0.isInstalled })
    else { return }
    if let service {
      presentation.pendingLanguageID = language.id
      presentation.status = "Switching to \(language.name)…"
      suggestionTask?.cancel()
      suggestionTask = nil
      service.changeLanguage(language)
      onChange()
    } else {
      beginCapture(language: language)
    }
  }

  private func refreshReasoningAvailability(_ language: SpeechLanguage) {
    availabilityTask?.cancel()
    presentation.reasoningNotice = "Checking local notes availability…"
    availabilityTask = Task { [weak self] in
      let notice = await LocalReasoningService.shared.availabilityNotice(
        localeIdentifier: language.isAutomatic ? nil : language.id)
      guard !Task.isCancelled else { return }
      self?.presentation.reasoningNotice = notice
    }
  }

  private func apply(_ update: AudioCaptureUpdate) {
    guard presentation.canFinish else { return }
    switch update {
    case .preparing(let message): presentation.status = message
    case .capturing(let label):
      presentation.phase = .capturing
      presentation.sourceLabel = label
      presentation.status = request.kind == .record ? "Recording microphone" : "Transcribing"
    case .changingLanguage(let language):
      presentation.pendingLanguageID = language.id
      presentation.status = "Switching to \(language.name)…"
    case .languageChanged(let language):
      presentation.selectedLanguageID = language.id
      presentation.pendingLanguageID = nil
      languages.preferences.remember(language, for: presentation.model)
      refreshReasoningAvailability(language)
      if presentation.phase != .preparing {
        presentation.status =
          presentation.isPaused
          ? "Paused" : (request.kind == .record ? "Recording microphone" : "Transcribing")
      }
    case .transcript(let text, let level, let elapsed):
      presentation.transcript = text
      presentation.elapsed = elapsed
      presentation.audioLevel = presentation.isPaused ? 0 : level
    case .failed(let failure):
      presentation.pendingLanguageID = nil
      presentation.phase = .failed(failure)
      presentation.status = "Stopped · Open details"
      presentation.audioLevel = 0
    case .transcriptionStopped(let failure):
      presentation.transcriptionFailure = failure
      presentation.pendingLanguageID = nil
      presentation.status = "Recording · Transcription stopped"
      suggestionTask?.cancel()
      suggestionTask = nil
    case .speakerDetectionNotice(let message):
      presentation.speakerDetectionNotice = message
    }
    onChange()
  }

  private func pause() {
    guard presentation.phase == .capturing else { return }
    service?.pause()
    presentation.phase = .paused
    presentation.status = "Paused"
    presentation.audioLevel = 0
    suggestionTask?.cancel()
    suggestionTask = nil
    onChange()
  }

  private func resume() {
    guard presentation.phase == .paused else { return }
    service?.resume()
    presentation.phase = .capturing
    presentation.status =
      presentation.transcriptionFailure == nil
      ? (request.kind == .record ? "Recording microphone" : "Transcribing")
      : "Recording · Transcription stopped"
    onChange()
  }

  func tick(_ context: SkillTickContext) -> SkillTickDisposition {
    service?.refreshProgress()
    considerSuggestion()
    return .keepRunning(statusDetail: presentation.statusLine, audioLevel: presentation.audioLevel)
  }

  private func considerSuggestion() {
    guard request.kind == .participate, presentation.phase == .capturing,
      presentation.pendingLanguageID == nil, presentation.suggestionsEnabled,
      presentation.reasoningNotice == nil, presentation.transcriptionFailure == nil,
      suggestionTask == nil,
      presentation.elapsed - lastSuggestionCheck >= Self.suggestionCheckInterval,
      presentation.transcript.count >= Self.minimumSourceCharacters,
      presentation.transcript != lastSuggestionSource
    else { return }
    let source = presentation.transcript
    let elapsed = presentation.elapsed
    let language = presentation.selectedLanguageID
    lastSuggestionSource = source
    lastSuggestionCheck = elapsed
    suggestionTask = Task { [weak self] in
      let suggestion = await LocalReasoningService.shared.suggestion(
        source: source, elapsed: elapsed, localeIdentifier: language)
      guard !Task.isCancelled, let self else { return }
      self.suggestionTask = nil
      guard self.presentation.phase == .capturing, self.presentation.suggestionsEnabled,
        let suggestion, self.suggestionGate.accept(suggestion, source: source)
      else { return }
      self.presentation.suggestions = self.suggestionGate.suggestions
      self.presentation.hasUnreadSuggestion = true
      self.onChange()
    }
  }

  func finish(
    _ context: SkillFinalizeContext,
    completion: @escaping @MainActor (SkillCompletionOutcome?) -> Void
  ) {
    guard presentation.canFinish else {
      completion(nil)
      return
    }
    let service = service
    self.service = nil
    stopReceivingUpdates()
    stopReasoning()
    presentation.phase = .finishing
    presentation.status = "Saving audio and transcript…"
    onChange()
    let id = recordID
    let kind = request.kind
    let suggestions = presentation.suggestions
    let transcription = SessionTranscriptionMetadata(
      languageIdentifier: presentation.selectedLanguageID,
      provenance: presentation.model.provenance,
      diarizationProvenance: presentation.diarizationModel?.provenance)
    let completed: @Sendable (AudioCaptureResult) -> Void = { [weak self] result in
      let outcome = Self.makeOutcome(
        result,
        context: .init(
          finalize: context, id: id, kind: kind, suggestions: suggestions,
          transcription: transcription))
      MainRunLoopDelivery.perform { [weak self] in
        self?.presentation.transcript = result.preview
        self?.presentation.speakerDetectionNotice = result.speakerDetectionNotice
        self?.presentation.elapsed = result.duration
        self?.presentation.phase = .finished
        self?.presentation.status = outcome.bannerSummary
        self?.presentation.savedRecordID = outcome.record.id
        completion(outcome)
      }
    }
    if let service {
      service.finish(completion: completed)
    } else {
      completed(AudioCaptureResult(transcript: "", recordingURL: nil, duration: 0, failure: nil))
    }
  }

  private struct CompletionContext: Sendable {
    let finalize: SkillFinalizeContext
    let id: UUID
    let kind: CompanionSkillKind
    let suggestions: [MeetingSuggestion]
    let transcription: SessionTranscriptionMetadata
  }

  nonisolated private static func makeOutcome(
    _ result: AudioCaptureResult, context: CompletionContext
  ) -> SkillCompletionOutcome {
    let hasText = !result.transcript.isEmpty
    let record = SessionRecord(
      kind: context.kind,
      origin: .init(
        characterID: context.finalize.companionID, characterName: context.finalize.companionName,
        source: .init(
          appName: context.finalize.target?.appName ?? "Microphone",
          bundleIdentifier: context.finalize.target?.bundleIdentifier,
          windowTitle: context.finalize.target?.windowTitle)),
      content: .init(
        text: .init(transcript: result.transcript),
        notes: .init(
          summary: hasText ? "Preparing local notes…" : "No speech was transcribed.",
          suggestions: context.suggestions),
        attachments: .init(audioFilename: result.recordingURL?.lastPathComponent),
        processing: .init(
          summaryPending: hasText, failure: result.failure,
          note: result.speakerDetectionNotice ?? "")),
      metadata: .init(
        id: context.id, durationSeconds: result.duration,
        transcription: context.transcription))
    let banner =
      result.failure != nil
      ? "Session needs attention · View details"
      : (hasText ? "Transcript ready · Preparing notes" : "Session finished · View details")
    return SkillCompletionOutcome(record: record, image: nil, bannerSummary: banner)
  }

  private func stopReasoning() {
    languageTask?.cancel()
    languageTask = nil
    suggestionTask?.cancel()
    suggestionTask = nil
    availabilityTask?.cancel()
    availabilityTask = nil
  }

  private func stopReceivingUpdates() {
    updateDelivery?.stop()
    updateDelivery = nil
  }

  func cancel() {
    stopReceivingUpdates()
    stopReasoning()
    service?.finish { _ in }
    service = nil
  }
}
