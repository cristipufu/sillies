import CoreGraphics
import Foundation

/// Pointer prediction requires proof that the application really started moving its window.
public struct WindowDragSession: Sendable {
  private static let historyDuration: TimeInterval = 0.8
  private static let maxSampleCount = 512
  private static let minimumMovementThreshold: Double = 1
  private static let sizeStabilityTolerance: Double = 0.5
  private static let initialMatchTolerance: Double = 8
  private static let confirmationGracePeriod: TimeInterval = 0.2
  private static let sustainedMismatchDuration: TimeInterval = 0.15

  public enum Mode: Sendable { case pending, pointer, metadata }
  public enum Decision: Sendable { case ignore, usePointer, useMetadata }
  private struct Sample: Sendable {
    let point: CGPoint
    let time: TimeInterval
  }

  public private(set) var gesture: PointerWindowGesture
  public private(set) var mode = Mode.pending
  public var startedAt: TimeInterval { gesture.startedAt }
  private var samples: [Sample] = []
  private var confirmedAt: TimeInterval = 0
  private var mismatchSince: TimeInterval?
  private var reanchoredPending = false

  public init(gesture: PointerWindowGesture) {
    self.gesture = gesture
    record(pointer: gesture.initialPointer, at: gesture.startedAt)
  }

  public mutating func record(pointer: CGPoint, at time: TimeInterval) {
    if samples.last?.point == pointer { samples.removeLast() }
    samples.append(Sample(point: pointer, time: time))
    samples.removeAll { time - $0.time > Self.historyDuration }
    if samples.count > Self.maxSampleCount {
      samples.removeFirst(samples.count - Self.maxSampleCount)
    }
  }

  public mutating func observe(_ frame: CGRect, capturedAt: TimeInterval, now: TimeInterval)
    -> Decision
  {
    guard capturedAt >= startedAt else { return .ignore }
    switch mode {
    case .pending:
      let initial = gesture.initialFrame
      let changed =
        abs(frame.minX - initial.minX) + abs(frame.minY - initial.minY)
        + abs(frame.width - initial.width) + abs(frame.height - initial.height)
      guard changed > Self.minimumMovementThreshold else { return .useMetadata }
      let movedWithoutResizing =
        abs(frame.width - initial.width) < Self.sizeStabilityTolerance
        && abs(frame.height - initial.height) < Self.sizeStabilityTolerance
      if movedWithoutResizing {
        gesture = PointerWindowGesture(
          kind: .move, frame: initial, pointer: gesture.initialPointer, at: startedAt)
      }
      if gesture.matches(
        frame, recentPointers: samples.map(\.point), tolerance: Self.initialMatchTolerance)
      {
        mode = .pointer
        confirmedAt = now
        return .usePointer
      }
      // Custom toolbars may apply a small drag threshold before starting native window movement.
      if movedWithoutResizing, !reanchoredPending, let latest = samples.last {
        reanchoredPending = true
        gesture = PointerWindowGesture(
          kind: .move, frame: frame, pointer: latest.point, at: startedAt)
        return .useMetadata
      }
      mode = .metadata
      return .useMetadata
    case .pointer:
      if gesture.matches(frame, recentPointers: samples.map(\.point)) {
        mismatchSince = nil
        return .usePointer
      }
      guard now - confirmedAt > Self.confirmationGracePeriod else { return .ignore }
      if mismatchSince == nil { mismatchSince = now }
      guard now - (mismatchSince ?? now) > Self.sustainedMismatchDuration else { return .ignore }
      // Keep the drag session alive: constrained windows still need fast geometry reads.
      mode = .metadata
      return .useMetadata
    case .metadata:
      return .useMetadata
    }
  }

  public func predictedFrame(at pointer: CGPoint) -> CGRect? {
    mode == .pointer ? gesture.frame(at: pointer) : nil
  }
}
