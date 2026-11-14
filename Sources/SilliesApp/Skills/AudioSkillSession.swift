import Foundation
import SilliesAudio
import SilliesCore
import SilliesReasoning
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
  private let reasoning: any LocalReasoning
  private let request: AudioSkillRequest
  private let captureFactory: SessionAudioCaptureFactory
  private let languages: AudioLanguageEnvironment
  private let onChange: () -> Void
  private let recordID = UUID()
  private var service: (any SessionAudioCapture)?
  private let callSpeakers: CallSpeakerMonitor?
  private var updateDelivery: AudioSessionUpdateDelivery?
  private var suggestionTask: Task<Void, Never>?
  private var availabilityTask: Task<Void, Never>?
  private var languageTask: Task<Void, Never>?
  private var suggestionGate = MeetingSuggestionGate()
  private var lastSuggestionCheck: TimeInterval = 0
  private var lastSuggestionSource = ""
  private var recoveringChannels: Set<UUID> = []

  init(
    request: AudioSkillRequest,
    services: AudioSkillServices, onChange: @escaping () -> Void
  ) {
    self.captureFactory = services.captureFactory
    self.languages = services.languages
    self.reasoning = services.reasoning
    callSpeakers =
      request.kind == .record ? nil : CallSpeakerMonitor(reader: services.makeCallSpeakerReader())
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
    presentation.onRefreshReasoningAvailability = { [weak self] in
      guard let self, self.service != nil, self.presentation.canFinish,
        let language = self.presentation.selectedLanguage
      else { return }
      self.refreshReasoningAvailability(language)
    }
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
        self.presentation.status = String(
          localized: "Transcription model unavailable · Open Settings")
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
          ? String(localized: "No speech model · Open details")
          : String(localized: "Choose language · Open details")
        self.onChange()
      }
    }
  }

  private func beginCapture(language: SpeechLanguage) {
    presentation.selectedLanguageID = language.id
    presentation.status = String(localized: "Preparing \(language.name)…")
    let url = request.recordingDirectory.appendingPathComponent("\(recordID.uuidString).m4a")
    var configuration = AudioCaptureConfiguration(
      kind: request.kind, target: request.target, recordingURL: url, language: language)
    configuration.recognitionContext.purpose = .continuousTranscription
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
      presentation.status = String(localized: "Switching to \(language.name)…")
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
    presentation.reasoningAvailability = .checking
    availabilityTask = Task { [weak self, reasoning] in
      let notice = await reasoning.availabilityNotice(
        localeIdentifier: language.isAutomatic ? nil : language.id)
      guard !Task.isCancelled else { return }
      self?.presentation.reasoningAvailability =
        notice.map {
          .unavailable($0)
        } ?? .available
    }
  }

  private func apply(_ update: AudioCaptureUpdate) {
    guard presentation.canFinish else { return }
    switch update {
    case .speechStarted, .speechEnded, .speechAssessment: break
    case .preparing(let message): presentation.status = message
    case .capturing(let label):
      presentation.phase = .capturing
      presentation.sourceLabel = label
      updateCaptureStatus()
    case .changingLanguage(let language):
      presentation.pendingLanguageID = language.id
      presentation.status = String(localized: "Switching to \(language.name)…")
    case .languageChanged(let language):
      recoveringChannels.removeAll()
      presentation.isRecoveringTranscription = false
      presentation.selectedLanguageID = language.id
      presentation.pendingLanguageID = nil
      languages.preferences.remember(language, for: presentation.model)
      refreshReasoningAvailability(language)
      if presentation.phase != .preparing {
        updateCaptureStatus()
      }
    case .transcript(let text, let level, let elapsed):
      presentation.transcript = text
      presentation.elapsed = elapsed
      presentation.audioLevel = presentation.isPaused ? 0 : level
    case .failed(let failure):
      callSpeakers?.stop()
      presentation.pendingLanguageID = nil
      presentation.phase = .failed(failure)
      presentation.status = String(localized: "Stopped · Open details")
      presentation.audioLevel = 0
    case .transcriptionStopped(let failure):
      callSpeakers?.stop()
      recoveringChannels.removeAll()
      presentation.isRecoveringTranscription = false
      presentation.transcriptionFailure = failure
      presentation.pendingLanguageID = nil
      presentation.status = String(localized: "Recording · Transcription stopped")
      suggestionTask?.cancel()
      suggestionTask = nil
    case .transcriptionRecovery(let recovery):
      switch recovery.phase {
      case .retrying, .catchingUp: recoveringChannels.insert(recovery.channel)
      case .caughtUp, .stopped: recoveringChannels.remove(recovery.channel)
      }
      presentation.isRecoveringTranscription = !recoveringChannels.isEmpty
      if presentation.transcriptionFailure == nil { updateCaptureStatus() }
    case .speakerDetectionNotice(let message):
      presentation.speakerDetectionNotice = message
    }
    onChange()
  }

  private func updateCaptureStatus() {
    if presentation.isPaused {
      presentation.status = String(localized: "Paused")
    } else if presentation.transcriptionFailure != nil {
      presentation.status = String(localized: "Recording · Transcription stopped")
    } else if presentation.isRecoveringTranscription {
      presentation.status = String(localized: "Transcription is catching up. Recording continues.")
    } else {
      presentation.status =
        request.kind == .record
        ? String(localized: "Recording microphone") : String(localized: "Transcribing")
    }
  }

  private func pause() {
    guard presentation.phase == .capturing else { return }
    callSpeakers?.suspend()
    service?.pause()
    presentation.phase = .paused
    presentation.status = String(localized: "Paused")
    presentation.audioLevel = 0
    suggestionTask?.cancel()
    suggestionTask = nil
    onChange()
  }

  private func resume() {
    guard presentation.phase == .paused else { return }
    service?.resume()
    presentation.phase = .capturing
    updateCaptureStatus()
    onChange()
  }

  func tick(_ context: SkillTickContext) -> SkillTickDisposition {
    service?.refreshProgress()
    if presentation.phase == .capturing, let service {
      callSpeakers?.tick(context, capture: service)
    }
    considerSuggestion()
    return .keepRunning(statusDetail: presentation.statusLine, audioLevel: presentation.audioLevel)
  }

  private func considerSuggestion() {
    guard request.kind == .participate, presentation.phase == .capturing,
      presentation.pendingLanguageID == nil, presentation.suggestionsEnabled,
      presentation.reasoningAvailability.isAvailable, presentation.transcriptionFailure == nil,
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
    suggestionTask = Task { [weak self, reasoning] in
      let suggestion = await reasoning.suggestion(
        source: source, elapsed: elapsed, localeIdentifier: language)
      guard !Task.isCancelled, let self else { return }
      self.suggestionTask = nil
      guard self.presentation.phase == .capturing, self.presentation.suggestionsEnabled,
        let suggestion, self.suggestionGate.accept(suggestion, source: source)
      else { return }
      self.presentation.updateSuggestions(self.suggestionGate.suggestions)
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
    let preparationFailure = presentation.captureFailure
    self.service = nil
    stopReceivingUpdates()
    stopReasoning()
    presentation.phase = .finishing
    presentation.status = String(localized: "Saving audio and transcript…")
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
        self?.presentation.complete(
          result, recordID: outcome.record.id, status: outcome.bannerSummary)
        completion(outcome)
      }
    }
    if let service {
      service.finish(ending: context.endReason, completion: completed)
    } else {
      completed(
        AudioCaptureResult(
          transcript: "", recordingURL: nil, duration: 0, failure: preparationFailure))
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
    var sourceText = SessionContent.Text(transcript: result.transcript)
    sourceText.segments = result.segments
    var record = SessionRecord(
      kind: context.kind,
      origin: .init(
        characterID: context.finalize.companionID, characterName: context.finalize.companionName,
        source: .init(
          appName: context.finalize.target?.appName ?? "Microphone",
          bundleIdentifier: context.finalize.target?.bundleIdentifier,
          windowTitle: context.finalize.target?.windowTitle)),
      content: .init(
        text: sourceText,
        notes: .init(
          summary: hasText
            ? String(localized: "Preparing local notes…")
            : String(localized: "No speech was transcribed."),
          suggestions: context.suggestions),
        attachments: .init(audioFilename: result.recordingURL?.lastPathComponent),
        processing: .init(
          summaryPending: hasText, failure: result.failure,
          note: result.speakerDetectionNotice ?? "")),
      metadata: .init(
        id: context.id, durationSeconds: result.duration,
        transcription: context.transcription))
    record.originalSpeakerTranscript = result.originalTranscript
    let banner =
      result.failure != nil
      ? String(localized: "Session needs attention · View details")
      : (hasText
        ? String(localized: "Transcript ready · Preparing notes")
        : String(localized: "Session finished · View details"))
    return SkillCompletionOutcome(record: record, image: nil, bannerSummary: banner)
  }

  private func stopReasoning() {
    languageTask?.cancel()
    languageTask = nil
    suggestionTask?.cancel()
    suggestionTask = nil
    availabilityTask?.cancel()
    availabilityTask = nil
    if presentation.reasoningAvailability == .checking {
      presentation.reasoningAvailability = .unchecked
    }
  }

  private func stopReceivingUpdates() {
    callSpeakers?.stop()
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
