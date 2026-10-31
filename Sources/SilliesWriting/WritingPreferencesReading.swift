import SilliesCore

@MainActor package protocol WritingPreferencesReading: AnyObject {
  var style: DictationOutputStyle { get }
  var languageIdentifier: String { get }
}
