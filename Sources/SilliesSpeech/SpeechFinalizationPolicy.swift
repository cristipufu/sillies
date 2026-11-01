/// Only stateless, complete-window engines can finalize a draft without another prediction.
package enum SpeechFinalizationPolicy: Sendable {
  case decode
  case reuseUnchangedDraft
}
