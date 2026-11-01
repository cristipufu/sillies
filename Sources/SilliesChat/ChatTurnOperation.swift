import Foundation
import SilliesCore
import SilliesReasoning
import SilliesTTS

/// Joins both branches before returning, including errors and cancellation. No orphaned speech task.
struct ChatTurnOperation: Sendable {
  enum Output: Sendable { case text, spoken }
  enum VoiceResult: Sendable {
    case finished
    case notice(String)
    case failed(SessionFailure)
  }
  struct Result: Sendable {
    let reply: ChatReply
    let voice: VoiceResult
  }
  struct Delivery: Sendable {
    let progress: @Sendable (ChatProgress) -> Void
    let text: @Sendable (String) async -> Void
    let textFinished: @Sendable () async -> Void
    let playback: @Sendable (SpeechPlaybackUpdate) -> Void
  }
  let services: ChatServices
  let delivery: Delivery

  func run(_ context: ChatContext, output: Output) async throws -> Result {
    let stream = ChatTurnStream(receive: delivery.text)
    let voice = Task { () -> VoiceResult in
      guard output == .spoken else {
        await stream.stopSpeech()
        return .finished
      }
      do {
        let notice = try await services.speech.speakStream(
          .init(id: context.turnID, text: "", profile: context.profile), text: stream.speech,
          receive: delivery.playback)
        await stream.stopSpeech()
        return notice.map(VoiceResult.notice) ?? .finished
      } catch {
        await stream.stopSpeech()
        return .failed(SessionFailure(error, category: .speechSynthesis))
      }
    }
    return try await withTaskCancellationHandler {
      do {
        let reply = try await services.conversation.streamReply(
          to: context, progress: delivery.progress, receive: stream.append)
        try Task.checkCancellation()
        try await stream.finish(reply.text)
        if output == .spoken { await delivery.textFinished() }
        let voiceResult = await voice.value
        try Task.checkCancellation()
        return Result(reply: reply, voice: voiceResult)
      } catch {
        await stream.cancel()
        voice.cancel()
        await services.speech.stop(id: context.turnID)
        _ = await voice.value
        throw error
      }
    } onCancel: {
      voice.cancel()
      Task {
        await stream.cancel()
        await services.speech.stop(id: context.turnID)
      }
    }
  }
}
