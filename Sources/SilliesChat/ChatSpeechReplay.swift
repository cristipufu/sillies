import Foundation
import SilliesTTS

/// Re-synthesize only retained phrases. Never invokes reasoning, searches or memory tools.
struct ChatSpeechReplay: Sendable {
  let output: any ChatSpeechOutput
  let request: ChatSpeechRequest
  let phrases: [String]

  func run(receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void) async throws -> String? {
    let stream = SpeechTextStream()
    let producer = Task {
      do {
        for phrase in phrases { try await stream.append(phrase) }
        await stream.finish()
      } catch {
        await stream.fail(error)
        throw error
      }
    }
    return try await withTaskCancellationHandler {
      do {
        let notice = try await output.speakStream(request, text: stream, receive: receive)
        producer.cancel()
        await stream.cancel()
        _ = await producer.result
        try Task.checkCancellation()
        return notice
      } catch {
        producer.cancel()
        await stream.cancel()
        await output.stop(id: request.id)
        _ = await producer.result
        throw error
      }
    } onCancel: {
      producer.cancel()
      Task {
        await stream.cancel()
        await output.stop(id: request.id)
      }
    }
  }
}
