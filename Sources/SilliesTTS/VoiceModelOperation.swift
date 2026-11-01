import Foundation

/// Preparation and speech share admission and cleanup, but speculation cannot preempt real work.
enum VoiceModelOperation: Sendable {
  enum Kind { case preparation, synthesis }
  case prepare(SpeechVoice, conversationID: UUID)
  case synthesize(SpeechSynthesisRequest, SynthesizedAudioSink)

  var kind: Kind {
    switch self {
    case .prepare: .preparation
    case .synthesize: .synthesis
    }
  }
  var voice: SpeechVoice {
    switch self {
    case .prepare(let voice, _): voice
    case .synthesize(let request, _): request.voice
    }
  }
  var conversationID: UUID? {
    switch self {
    case .prepare(_, let id): id
    case .synthesize(let request, _): request.conversationID
    }
  }
  func run(on model: any PreparedTTSModel) async throws {
    switch self {
    case .prepare(let voice, _): try await model.prepareVoice(voice)
    case .synthesize(let request, let receive):
      try await model.synthesize(request, receive: receive)
    }
  }
}
