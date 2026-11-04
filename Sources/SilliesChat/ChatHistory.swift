import Foundation
import Observation
import SilliesCore

/// Owns persistence state, not inference or presentation. Failed writes remain available for Retry.
@MainActor @Observable
package final class ChatHistory {
  private struct Write {
    let id: UUID
    let revision: UInt64
    let task: Task<Void, Error>
  }
  private static let maximumMemoryReceipts = 40
  private static let autosaveInterval: Duration = .milliseconds(400)
  package let configuration: ChatHistoryConfiguration
  package private(set) var handle: ConversationHandle?
  package private(set) var checkpoint = ConversationCheckpoint()
  package private(set) var isLoaded: Bool
  package private(set) var failure: String?
  package let memories: ChatMemoryBrowser
  package private(set) var memoryReceipts: [MemoryReceipt] = []
  @ObservationIgnored private var buffer = ConversationWriteBuffer()
  @ObservationIgnored private var write: Write?
  @ObservationIgnored private var autosave: Task<Void, Never>?
  @ObservationIgnored private var stopped = false
  package var hasUnsavedChanges: Bool { buffer.needsSave || write != nil }

  package init(configuration: ChatHistoryConfiguration) {
    self.configuration = configuration
    memories = ChatMemoryBrowser(repository: configuration.memories)
    isLoaded = configuration.conversations == nil
  }

  package func load(_ owner: ConversationOwner) async throws -> ConversationSnapshot? {
    guard let repository = configuration.conversations else { return nil }
    do {
      let snapshot = try await repository.open(owner)
      try Task.checkCancellation()
      restore(snapshot)
      try await refreshMemories()
      return snapshot
    } catch {
      isLoaded = false
      recordFailure(error)
      throw error
    }
  }

  package func restore(_ snapshot: ConversationSnapshot) {
    memories.invalidate()
    handle = snapshot.handle
    checkpoint = snapshot.checkpoint
    buffer = .init()
    failure = nil
    isLoaded = true
    stopped = false
  }

  package func resumeSaving() {
    stopped = false
    if buffer.needsSave { scheduleSave() }
  }

  package func stage(_ message: ChatMessage) {
    guard isLoaded, handle != nil else { return }
    buffer.stage(message)
    scheduleSave()
  }
  package func remove(_ id: UUID) {
    guard isLoaded, handle != nil else { return }
    buffer.remove(id)
    scheduleSave()
  }
  package func update(_ checkpoint: ConversationCheckpoint) {
    guard isLoaded, handle != nil, checkpoint != self.checkpoint else { return }
    self.checkpoint = checkpoint
    buffer.changedCheckpoint()
    scheduleSave()
  }

  package func flush() async throws {
    guard isLoaded else { throw ConversationStorageError.invalidData }
    while write != nil || buffer.needsSave {
      guard let current = write ?? beginWrite() else { return }
      do {
        try await current.task.value
        acknowledge(current)
        if stopped { return }
      } catch {
        if write?.id == current.id { write = nil }
        recordFailure(error)
        throw error
      }
    }
  }

  /// Detached I/O and supplied run-loop delivery also work during AppKit's modal termination loop.
  package func stopAndFlush(
    deliver: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
    completion: @escaping @MainActor @Sendable () -> Void
  ) {
    stopped = true
    memories.invalidate()
    autosave?.cancel()
    autosave = nil
    guard let repository = configuration.conversations, let handle, isLoaded else {
      completion()
      return
    }
    let preceding = write?.task
    let update = buffer.update(handle: handle, checkpoint: checkpoint, at: Date())
    let revision = buffer.revision
    Task.detached { [self] in
      do {
        if let preceding {
          do { try await preceding.value } catch {
            fputs("Conversation pending write will be retried: \(error)\n", stderr)
          }
        }
        try await repository.save(update)
        deliver {
          self.buffer.acknowledge(revision)
          self.write = nil
          self.failure = nil
          completion()
        }
      } catch {
        let message = error.localizedDescription
        fputs("Conversation final save failed: \(error)\n", stderr)
        deliver {
          self.failure = message
          self.write = nil
          completion()
        }
      }
    }
  }

  package func refreshMemories() async throws {
    guard let repository = configuration.memories, let handle else { return }
    try await memories.refresh(handle)
    let receipts = try await repository.recentMemoryChanges(handle)
    guard self.handle == handle else { return }
    memoryReceipts = receipts
  }

  package func receivedMemory(_ receipt: MemoryReceipt) {
    memories.received(receipt)
    memoryReceipts.removeAll { $0.id == receipt.id }
    memoryReceipts.insert(receipt, at: 0)
    memoryReceipts = Array(memoryReceipts.prefix(Self.maximumMemoryReceipts))
  }

  private func scheduleSave() {
    guard !stopped, failure == nil, autosave == nil else { return }
    autosave = Task { [weak self] in
      do { try await Task.sleep(for: Self.autosaveInterval) } catch { return }
      guard let self else { return }
      self.autosave = nil
      do { try await self.flush() } catch {
        // The failed write stays available.
      }
    }
  }

  private func beginWrite() -> Write? {
    guard let repository = configuration.conversations, let handle else { return nil }
    let update = buffer.update(handle: handle, checkpoint: checkpoint, at: Date())
    let created = Write(
      id: UUID(), revision: buffer.revision,
      task: Task.detached(priority: .utility) { try await repository.save(update) })
    write = created
    return created
  }

  private func acknowledge(_ completed: Write) {
    guard write?.id == completed.id else { return }
    buffer.acknowledge(completed.revision)
    write = nil
    failure = nil
  }

  package func recordFailure(_ error: Error) {
    failure = error.localizedDescription
    fputs("Conversation history failed: \(error)\n", stderr)
  }
}
