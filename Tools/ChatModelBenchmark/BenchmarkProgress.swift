import Foundation
import SilliesCore
import Synchronization

/// Preserve checkpoints even when generation fails, just as the Chat session does.
final class BenchmarkProgress: Sendable {
  struct Snapshot: Sendable {
    var memory: ConversationMemory?
    var sources: [ChatSource] = []
    var memoryCommitSeconds: [Double] = []
  }
  private struct State {
    var snapshot = Snapshot()
    var rememberedReceipts: Set<UUID> = []
  }
  private let state = Mutex(State())
  private let start: ContinuousClock.Instant

  init(start: ContinuousClock.Instant) { self.start = start }

  func receive(_ progress: ChatProgress) {
    state.withLock { value in
      switch progress {
      case .memory(let memory): value.snapshot.memory = memory
      case .sources(let sources): value.snapshot.sources = sources
      case .remembered(let receipt):
        guard value.rememberedReceipts.insert(receipt.id).inserted else { return }
        value.snapshot.memoryCommitSeconds.append(
          BenchmarkTurnTrace.seconds(start.duration(to: .now)))
      case .compacting, .usingTool: break
      }
    }
  }

  var snapshot: Snapshot { state.withLock { $0.snapshot } }
}
