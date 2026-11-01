import Foundation

/// Idle helpers still hold weights. Evict an incompatible idle model before loading its peer.
actor InferenceModelResidency {
  enum Runtime: Sendable { case text, voice }
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
    let peer: Runtime = runtime == .text ? .voice : .text
    guard let resident = models[peer],
      reservation.bytes > budget || resident.bytes > budget - reservation.bytes
    else { return }
    models[peer] = nil
    await resident.evict()
  }
}
