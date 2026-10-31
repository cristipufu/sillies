import Foundation

/// Keeps the saved keys and legacy decoding separate from presentation and session data.
extension SessionRecord {
  private enum CodingKeys: String, CodingKey {
    case id
    case kind
    case characterID
    case characterName
    case appName
    case bundleIdentifier
    case windowTitle
    case createdAt
    case durationSeconds
    case transcript
    case extractedText
    case summary
    case actionItems
    case imageFilename
    case stashedItems
    case summaryPending
    case failure
    case speechProvenance
    case diarizationProvenance
    case isProtected, screenshotTextState
    case transcriptSegments, speakerNames, originalSpeakerTranscript
    case audioFilename, explanation, processingNote, suggestions, failureMessage, languageIdentifier
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    kind = try container.decode(CompanionSkillKind.self, forKey: .kind)
    characterID = try container.decode(String.self, forKey: .characterID)
    characterName = try container.decode(String.self, forKey: .characterName)
    appName = try container.decode(String.self, forKey: .appName)
    bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
    windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
    transcript = try container.decode(String.self, forKey: .transcript)
    extractedText = try container.decode(String.self, forKey: .extractedText)
    summary = try container.decode(String.self, forKey: .summary)
    actionItems = try container.decode([String].self, forKey: .actionItems)
    imageFilename = try container.decodeIfPresent(String.self, forKey: .imageFilename)
    stashedItems = try container.decode([String].self, forKey: .stashedItems)
    summaryPending = try container.decodeIfPresent(Bool.self, forKey: .summaryPending) ?? false
    failure =
      try container.decodeIfPresent(SessionFailure.self, forKey: .failure)
      ?? Self.legacyFailure(
        message: container.decodeIfPresent(String.self, forKey: .failureMessage), kind: kind)
    audioFilename = try container.decodeIfPresent(String.self, forKey: .audioFilename)
    explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
    processingNote = try container.decodeIfPresent(String.self, forKey: .processingNote) ?? ""
    suggestions =
      try container.decodeIfPresent([MeetingSuggestion].self, forKey: .suggestions) ?? []
    languageIdentifier = try container.decodeIfPresent(String.self, forKey: .languageIdentifier)
    speechProvenance = try container.decodeIfPresent(
      SpeechProvenance.self, forKey: .speechProvenance)
    diarizationProvenance = try container.decodeIfPresent(
      SpeechProvenance.self, forKey: .diarizationProvenance)
    isProtected = try container.decodeIfPresent(Bool.self, forKey: .isProtected) ?? false
    screenshotTextState =
      try container.decodeIfPresent(ScreenshotTextState.self, forKey: .screenshotTextState) ?? .none
    transcriptSegments =
      try container.decodeIfPresent([TranscriptSegment].self, forKey: .transcriptSegments) ?? []
    speakerNames =
      try container.decodeIfPresent([String: String].self, forKey: .speakerNames) ?? [:]
    originalSpeakerTranscript = try container.decodeIfPresent(
      String.self, forKey: .originalSpeakerTranscript)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(kind, forKey: .kind)
    try container.encode(characterID, forKey: .characterID)
    try container.encode(characterName, forKey: .characterName)
    try container.encode(appName, forKey: .appName)
    try container.encodeIfPresent(bundleIdentifier, forKey: .bundleIdentifier)
    try container.encodeIfPresent(windowTitle, forKey: .windowTitle)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(durationSeconds, forKey: .durationSeconds)
    try container.encode(transcript, forKey: .transcript)
    try container.encode(extractedText, forKey: .extractedText)
    try container.encode(summary, forKey: .summary)
    try container.encode(actionItems, forKey: .actionItems)
    try container.encodeIfPresent(imageFilename, forKey: .imageFilename)
    try container.encode(stashedItems, forKey: .stashedItems)
    try container.encode(summaryPending, forKey: .summaryPending)
    try container.encodeIfPresent(failureMessage, forKey: .failureMessage)
    try container.encodeIfPresent(failure, forKey: .failure)
    try container.encodeIfPresent(audioFilename, forKey: .audioFilename)
    try container.encode(explanation, forKey: .explanation)
    try container.encode(processingNote, forKey: .processingNote)
    try container.encode(suggestions, forKey: .suggestions)
    try container.encodeIfPresent(languageIdentifier, forKey: .languageIdentifier)
    try container.encodeIfPresent(speechProvenance, forKey: .speechProvenance)
    try container.encodeIfPresent(diarizationProvenance, forKey: .diarizationProvenance)
    try container.encode(isProtected, forKey: .isProtected)
    try container.encode(screenshotTextState, forKey: .screenshotTextState)
    try container.encode(transcriptSegments, forKey: .transcriptSegments)
    try container.encode(speakerNames, forKey: .speakerNames)
    try container.encodeIfPresent(originalSpeakerTranscript, forKey: .originalSpeakerTranscript)
  }

  /// Recognize only historical machine-generated errors, never words from a summary.
  private static func legacyFailure(message: String?, kind: CompanionSkillKind) -> SessionFailure? {
    guard let message else { return nil }
    if kind == .snap || kind == .explain, message == "Screen capture permission required" {
      return SessionFailure(
        category: .permissionDenied, message: message, recovery: .openScreenRecordingSettings)
    }
    if kind.isAudioSession,
      message
        == "Microphone permission needed. Enable Sillies in System Settings → Privacy & Security → Microphone."
    {
      return SessionFailure(
        category: .permissionDenied, message: message, recovery: .openMicrophoneSettings)
    }
    return SessionFailure(category: .unknown, message: message)
  }
}
