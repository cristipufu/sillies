import Foundation
import Observation
import SilliesAudio
import SilliesCore

@MainActor @Observable
final class AudioSessionPresentation {
  enum Phase: Equatable {
    case preparing, capturing, paused, finishing, finished
    case failed(String)
  }
  let kind: CompanionSkillKind
  var phase: Phase = .preparing
  var sourceLabel: String
  var status = "Preparing on-device speech…"
  var transcript = ""
  var followsLiveTranscript = true
  var elapsed: TimeInterval = 0
  var audioLevel: Double = 0
  var suggestionsEnabled: Bool
  var suggestions: [MeetingSuggestion] = []
  var hasUnreadSuggestion = false
  var currentBubbleSuggestion: MeetingSuggestion? {
    guard kind == .participate, phase == .capturing, suggestionsEnabled else { return nil }
    return suggestions.last
  }
  var reasoningNotice: String?
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

  init(kind: CompanionSkillKind, sourceLabel: String) {
    self.kind = kind
    self.sourceLabel = sourceLabel
    suggestionsEnabled = kind == .participate
  }

  var selectedLanguage: SpeechLanguage? { languages.first { $0.id == selectedLanguageID } }
  var displayedLanguage: SpeechLanguage? {
    languages.first { $0.id == (pendingLanguageID ?? selectedLanguageID) }
  }
  var canSelectLanguage: Bool {
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
