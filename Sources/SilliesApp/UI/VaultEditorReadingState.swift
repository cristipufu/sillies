import AppKit
import SilliesCore

/// Reading state is bounded and stays outside observable state while the user scrolls.
@MainActor final class VaultEditorReadingState {
  struct Position {
    let selection: NSRange
    let origin: NSPoint
  }
  private static let capacity = 64
  private var positions: [VaultBlockLocation: Position] = [:]
  private var order: [VaultBlockLocation] = []

  func save(_ position: Position, at location: VaultBlockLocation) {
    positions[location] = .init(
      selection: position.selection,
      origin: position.origin.x.isFinite && position.origin.y.isFinite ? position.origin : .zero)
    order.removeAll { $0 == location }
    order.append(location)
    if order.count > Self.capacity { positions.removeValue(forKey: order.removeFirst()) }
  }

  func position(at location: VaultBlockLocation) -> Position? { positions[location] }
  func latestLocation(recordID: UUID) -> VaultBlockLocation? {
    order.last { $0.recordID == recordID }
  }
}
