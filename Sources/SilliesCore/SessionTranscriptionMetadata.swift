public struct SessionTranscriptionMetadata: Sendable {
  public let languageIdentifier: String?
  public let provenance: SpeechProvenance?
  public let diarizationProvenance: SpeechProvenance?

  public init(
    languageIdentifier: String? = nil, provenance: SpeechProvenance? = nil,
    diarizationProvenance: SpeechProvenance? = nil
  ) {
    self.languageIdentifier = languageIdentifier
    self.provenance = provenance
    self.diarizationProvenance = diarizationProvenance
  }
}
