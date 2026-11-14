import FluidAudio
import SilliesSpeech

/// The encoder's native left context also determines the audio replayed after a bounded-window cut.
enum NemotronRecognitionConfiguration {
  private static let leftFrames = 70
  private static let chunkFrames = 7
  private static let rightFrames = 7

  static func native(language: NemotronUnifiedLanguage) -> UnifiedConfig {
    UnifiedConfig(
      leftFrames: leftFrames, chunkFrames: chunkFrames, rightFrames: rightFrames,
      family: .nemotronMultilingual(language))
  }

  static var channel: SpeechWindowConfiguration {
    let configuration = native(language: .auto)
    return SpeechWindowConfiguration(
      cadence: .streaming, continuousBoundaryMode: .adaptive,
      boundaryReplayDuration: Double(configuration.leftFrames * configuration.frameSamples)
        / Double(configuration.sampleRate))
  }
}
