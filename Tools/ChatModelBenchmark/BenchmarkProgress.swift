import SilliesCore
import Synchronization

/// Preserve checkpoints even when generation fails, just as the Chat session does.
final class BenchmarkProgress: Sendable {
  struct Snapshot: Sendable {
    var memory: ConversationMemory?
    var sources: [ChatSource] = []
  }
  private let state = Mutex(Snapshot())

  func receive(_ progress: ChatProgress) {
    state.withLock { value in
      switch progress {
      case .memory(let memory): value.memory = memory
      case .sources(let sources): value.sources = sources
      case .compacting, .usingTool, .remembered: break
      }
    }
  }

  var snapshot: Snapshot { state.withLock { $0 } }
}
