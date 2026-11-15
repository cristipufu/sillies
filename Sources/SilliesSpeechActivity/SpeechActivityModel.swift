import Foundation
import SilliesInference
import SilliesModelStore
import SilliesSpeech

/// Prepared validators retain one model with their recognition lifetime, never a process-global cache.
package struct SpeechActivityModel: SpeechWindowValidating {
  package static let directoryName = "silero-vad-unified-256ms-v6.2.1.mlmodelc"
  private let queue: SpeechOperationQueue<[Float], Bool>

  init(validator: any SpeechWindowValidating, activity: InferenceActivity) {
    queue = SpeechOperationQueue { samples in
      try await activity.performSpeech { try await validator.containsSpeech(samples) }
    }
  }

  package static func load(lease: InstalledModelLease, activity: InferenceActivity) async throws
    -> Self
  {
    let engine = NativeSpeechActivityEngine(lease: lease)
    try await activity.prepareSpeechRuntime {
      try await engine.load(lease.directory.appendingPathComponent(directoryName))
    }
    return Self(validator: engine, activity: activity)
  }

  package func containsSpeech(_ samples: [Float]) async throws -> Bool {
    try await queue.submit(samples, priority: Task.currentPriority)
  }
}

extension NativeSpeechActivityEngine: SpeechWindowValidating {}
