import Foundation
import Observation
import SilliesAudio
import SilliesCore
import SilliesSpeech

@MainActor @Observable
final class AudioSessionPresentation {
  enum Phase: Equatable {
    case preparing, capturing, paused, finishing, finished
    case failed(SessionFailure)
  }
  enum DetailPane: Hashable { case transcript, suggestions }
  enum ReasoningAvailability: Equatable {
    case unchecked, checking, available
    case unavailable(String)

    var isAvailable: Bool { self == .available }
    var failureMessage: String? {
      if case .unavailable(let message) = self { return message }
      return nil
    }
    var statusMessage: String? {
      switch self {
      case .checking: return String(localized: "Checking local notes availability…")
      case .unchecked, .available: return nil
      case .unavailable:
        return String(localized: "AI notes are unavailable. Transcription is unaffected.")
      }
    }
  }
  let kind: CompanionSkillKind
  var model: SpeechModelDescriptor = .apple
  var diarizationModel: SpeechModelDescriptor?
  var speakerDetectionNotice: String?
  var transcriptionFailure: SessionFailure?
  var isRecoveringTranscription = false
  var phase: Phase = .preparing
  private var completionFailure: SessionFailure?
  var captureFailure: SessionFailure? {
    if case .failed(let failure) = phase { return failure }
    return completionFailure
  }
  var sourceLabel: String
  var status = String(localized: "Preparing on-device speech…")
  var transcript = ""
  var followsLiveTranscript = true
  var elapsed: TimeInterval = 0
  var audioLevel: Double = 0
  var suggestionsEnabled: Bool
  var suggestions: [MeetingSuggestion] = []
  var hasUnreadSuggestion = false
  private(set) var detailPane: DetailPane = .transcript
  private var isShowingDetails = false
  var currentBubbleSuggestion: MeetingSuggestion? {
    guard kind == .participate, phase == .capturing, suggestionsEnabled else { return nil }
    return suggestions.last
  }
  var reasoningAvailability: ReasoningAvailability = .unchecked
  var savedRecordID: UUID?
  var languages: [SpeechLanguage] = []
  var isLoadingLanguages = true
  var selectedLanguageID: String?
  var pendingLanguageID: String?
  var onSelectLanguage: ((String) -> Void)?
  var onPause: (() -> Void)?
  var onResume: (() -> Void)?
  var onFinish: (() -> Void)?
  var onOpenRecord: ((UUID) -> Void)?
  var onOpenTextModelSettings: (() -> Void)?
  var onRefreshReasoningAvailability: (() -> Void)?

  init(kind: CompanionSkillKind, sourceLabel: String) {
    self.kind = kind
    self.sourceLabel = sourceLabel
    suggestionsEnabled = kind == .participate
  }

  func selectDetailPane(_ pane: DetailPane) {
    detailPane = pane
    if pane == .suggestions { hasUnreadSuggestion = false }
  }

  func showDetails() {
    isShowingDetails = true
    if hasUnreadSuggestion { selectDetailPane(.suggestions) }
  }

  func hideDetails() { isShowingDetails = false }

  func updateSuggestions(_ suggestions: [MeetingSuggestion]) {
    self.suggestions = suggestions
    hasUnreadSuggestion = !suggestions.isEmpty && (!isShowingDetails || detailPane != .suggestions)
  }

  func complete(_ result: AudioCaptureResult, recordID: UUID, status: String) {
    transcript = result.preview
    speakerDetectionNotice = result.speakerDetectionNotice
    elapsed = result.duration
    completionFailure = result.failure
    phase = .finished
    self.status = status
    savedRecordID = recordID
    audioLevel = 0
    isLoadingLanguages = false
    pendingLanguageID = nil
    isRecoveringTranscription = false
  }

  var selectedLanguage: SpeechLanguage? { languages.first { $0.id == selectedLanguageID } }
  var displayedLanguage: SpeechLanguage? {
    languages.first { $0.id == (pendingLanguageID ?? selectedLanguageID) }
  }
  var canSelectLanguage: Bool {
    guard transcriptionFailure == nil else { return false }
    guard !isLoadingLanguages, pendingLanguageID == nil else { return false }
    return phase == .capturing || phase == .paused
      || (phase == .preparing && selectedLanguageID == nil)
  }
  var canPause: Bool { pendingLanguageID == nil && (phase == .capturing || phase == .paused) }
  var isPaused: Bool { phase == .paused }
  var isFinished: Bool { phase == .finished }
  var canFinish: Bool { phase != .finishing && phase != .finished }
  var statusLine: String { "\(SessionRecord.formatDuration(elapsed)) · \(status)" }
}
