import Foundation
import SilliesCore
import SilliesDiagnostics
import SilliesReasoning
import SilliesTTS

/// Joins both branches before returning, including errors and cancellation. No orphaned speech task.
struct ChatTurnOperation: Sendable {
  enum Output: Sendable { case text, spoken }
  enum VoiceResult: Sendable {
    case finished
    case preempted
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
    var plannedSpeech: @Sendable (String) -> Void = { _ in }
  }
  let services: ChatServices
  let delivery: Delivery
  var voiceLifetime: SpeechModelLifetime? = nil

  func run(_ context: ChatContext, output: Output) async throws -> Result {
    let stream = ChatTurnStream(
      receive: delivery.text, milestone: { delivery.playback(.milestone($0)) },
      plannedSpeech: delivery.plannedSpeech)
    let voice = Task { () -> VoiceResult in
      guard output == .spoken else {
        await stream.stopSpeech()
        return .finished
      }
      do {
        let notice = try await services.speech.speakStream(
          .init(id: context.turnID, text: "", profile: context.profile, lifetime: voiceLifetime),
          text: stream.speech,
          receive: delivery.playback)
        await stream.stopSpeech()
        return notice.map(VoiceResult.notice) ?? .finished
      } catch {
        await stream.stopSpeech()
        if error is CancellationError { return .preempted }
        services.diagnostics.record(
          .init(.synthesis, .failed, operation: context.turnID).failing(error))
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
        voice.cancel()
        await services.speech.stop(id: context.turnID)
        await stream.cancel()
        _ = await voice.value
        throw error
      }
    } onCancel: {
      voice.cancel()
      Task {
        await services.speech.stop(id: context.turnID)
        await stream.cancel()
      }
    }
  }
}
