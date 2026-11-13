import SilliesAudio
import SilliesDiagnostics
import SilliesReasoning

/// The composition root supplies the same reasoning owner to recording and writing.
struct AudioSkillServices {
  let captureFactory: SessionAudioCaptureFactory
  let languages: AudioLanguageEnvironment
  let reasoning: any LocalReasoning
  let makeCallSpeakerReader: @Sendable () -> any CallSpeakerReading
  var diagnostics: DiagnosticSink = .disabled
}
