import Foundation
import SilliesInference

/// Serializes shared recognition weights while preserving interactive priority and admission.
package actor SpeechInferenceScheduler: SpeechWindowEngine {
  package nonisolated let finalizationPolicy: SpeechFinalizationPolicy
  private let queue: SpeechOperationQueue<SpeechWindowRequest, SpeechWindowResult>

  package init(engine: any SpeechWindowEngine, activity: InferenceActivity = .shared) {
    finalizationPolicy = engine.finalizationPolicy
    queue = SpeechOperationQueue { request in
      try await activity.performSpeech { try await engine.transcribe(request) }
    }
  }

  package func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    try await queue.submit(request, priority: request.context.priority.taskPriority)
  }
}
