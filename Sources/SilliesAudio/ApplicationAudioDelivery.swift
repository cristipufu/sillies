import Foundation
import Synchronization

/// The device callback performs no actor hop and cannot publish an obsolete provider's packets.
final class ApplicationAudioDelivery: Sendable {
  private let selected = Mutex<UUID?>(nil)
  private let receivePacket: AudioCaptureInputQueue.Receiver
  init(receive: @escaping AudioCaptureInputQueue.Receiver) { receivePacket = receive }
  func select(_ generation: UUID) { selected.withLock { $0 = generation } }
  func stop() { selected.withLock { $0 = nil } }
  func receive(_ packet: AudioCaptureInputQueue.Packet, from generation: UUID) {
    guard selected.withLock({ $0 == generation }) else { return }
    receivePacket(packet)
  }
}
