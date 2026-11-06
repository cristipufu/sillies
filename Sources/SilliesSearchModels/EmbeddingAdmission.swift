import Foundation
import SilliesCore

/// Serialize the two durable index producers; interactive lookups fall back instead of queuing.
actor EmbeddingAdmission {
  private static let maximumWaiters = 8
  private var occupied = false
  private var stopped = false
  private var waiting: [(UUID, CheckedContinuation<Void, any Error>)] = []
  var pendingPassages: Int { waiting.count }

  func acquire(_ purpose: SearchEmbeddingInput.Purpose) async throws {
    try Task.checkCancellation()
    guard !stopped else { throw CancellationError() }
    if !occupied {
      occupied = true
      return
    }
    guard purpose == .passage, waiting.count < Self.maximumWaiters else {
      throw SearchEmbeddingError.unavailable
    }
    let id = UUID()
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try await withCheckedThrowingContinuation { waiting.append((id, $0)) }
    } onCancel: {
      Task { await self.cancel(id) }
    }
  }

  func release() {
    guard !waiting.isEmpty else {
      occupied = false
      return
    }
    waiting.removeFirst().1.resume()
  }

  func stop() {
    stopped = true
    let pending = waiting
    waiting.removeAll()
    for (_, continuation) in pending { continuation.resume(throwing: CancellationError()) }
  }

  private func cancel(_ id: UUID) {
    guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
    waiting.remove(at: index).1.resume(throwing: CancellationError())
  }
}
