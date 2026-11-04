import Foundation

/// Idle helpers still hold weights. Evict an incompatible idle model before loading its peer.
actor InferenceModelResidency {
  enum Runtime: Sendable { case text, voice, search }
  struct Resident: Sendable {
    let id: UUID
    let bytes: UInt64
    let evict: @Sendable () async -> Void
  }
  private let budget: UInt64
  private var models: [Runtime: Resident] = [:]
  init(budget: UInt64) { self.budget = budget }
  func remember(_ runtime: Runtime, resident: Resident) { models[runtime] = resident }
  func forget(_ runtime: Runtime, id: UUID) {
    if models[runtime]?.id == id { models[runtime] = nil }
  }
  func makeRoom(for runtime: Runtime, reservation: InferenceReservation) async {
    // Search is cheapest to reload. Account for all idle peers, not only a text/voice pair.
    for peer in [Runtime.search, .voice, .text] where peer != runtime {
      let available = reservation.bytes >= budget ? 0 : budget - reservation.bytes
      let retained = models.filter { $0.key != runtime }.values.reduce(UInt64(0)) {
        let sum = $0.addingReportingOverflow($1.bytes)
        return sum.overflow ? .max : sum.partialValue
      }
      guard retained > available, let resident = models.removeValue(forKey: peer) else { continue }
      await resident.evict()
    }
  }
}
