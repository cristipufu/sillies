import Foundation

/// Capture lifecycle and progress contract shared by producers and presenters.
package enum AudioCaptureUpdate: Sendable {
  case preparing(String)
  case capturing(String)
  case changingLanguage(SpeechLanguage)
  case languageChanged(SpeechLanguage)
  case transcript(String, level: Double, elapsed: TimeInterval)
  case failed(String)
}
