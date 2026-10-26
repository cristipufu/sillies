import CoreGraphics
import Foundation

/// Pointer prediction requires proof that the application really started moving its window.
public struct WindowDragSession: Sendable {
  private static let historyDuration: TimeInterval = 0.8
  private static let maxSampleCount = 512
  private static let pendingCaptureWindow: TimeInterval = 0.02
  private static let maxInterpolationDeltaTime: TimeInterval = 0.05
  private static let interpolationStepDistance: Double = 6
  private static let maxInterpolationSubdivisions = 16
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
  private struct MetadataObservation: Sendable {
    let frame: CGRect
    let pointer: CGPoint
    let capturedAt: TimeInterval
  }

  public private(set) var gesture: PointerWindowGesture
  public private(set) var mode = Mode.pending
  public var startedAt: TimeInterval { gesture.startedAt }
  private var samples: [Sample] = []
  private var confirmedAt: TimeInterval = 0
  private var mismatchSince: TimeInterval?
  private var reanchoredPending = false
  private var lastMetadataObservation: MetadataObservation?

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
        frame,
        recentPointers: pointerCandidates(near: capturedAt, window: Self.pendingCaptureWindow),
        tolerance: Self.initialMatchTolerance)
      {
        mode = .pointer
        confirmedAt = now
        return .usePointer
      }
      // Custom toolbars may apply a small drag threshold before starting native window movement.
      if movedWithoutResizing, let anchor = interpolatedPoint(at: capturedAt) {
        gesture = PointerWindowGesture(
          kind: .move, frame: frame, pointer: anchor, at: startedAt)
        if !reanchoredPending {
          reanchoredPending = true
          return .useMetadata
        }
        mode = .pointer
        confirmedAt = now
        return .usePointer
      }
      lastMetadataObservation = MetadataObservation(
        frame: frame,
        pointer: interpolatedPoint(at: capturedAt) ?? gesture.initialPointer,
        capturedAt: capturedAt)
      mode = .metadata
      return .useMetadata
    case .pointer:
      if gesture.matches(frame, recentPointers: subframePointerCandidates()) {
        mismatchSince = nil
        return .usePointer
      }
      guard now - confirmedAt > Self.confirmationGracePeriod else { return .ignore }
      if mismatchSince == nil { mismatchSince = now }
      guard now - (mismatchSince ?? now) > Self.sustainedMismatchDuration else { return .ignore }
      // Keep the drag session alive: constrained windows still need fast geometry reads.
      lastMetadataObservation = MetadataObservation(
        frame: frame,
        pointer: interpolatedPoint(at: capturedAt) ?? gesture.initialPointer,
        capturedAt: capturedAt)
      mode = .metadata
      return .useMetadata
    case .metadata:
      let currentPointer = interpolatedPoint(at: capturedAt) ?? gesture.initialPointer
      if let previous = lastMetadataObservation {
        let movedWithoutResizing =
          abs(frame.width - previous.frame.width) < Self.sizeStabilityTolerance
          && abs(frame.height - previous.frame.height) < Self.sizeStabilityTolerance
        let displacement =
          abs(frame.minX - previous.frame.minX) + abs(frame.minY - previous.frame.minY)
        if gesture.kind == .move,
          movedWithoutResizing,
          displacement > Self.minimumMovementThreshold
        {
          let candidate = PointerWindowGesture(
            kind: .move, frame: previous.frame, pointer: previous.pointer, at: startedAt)
          if candidate.matches(
            frame,
            recentPointers: pointerCandidates(near: capturedAt, window: Self.pendingCaptureWindow),
            tolerance: Self.initialMatchTolerance)
          {
            gesture = PointerWindowGesture(
              kind: .move, frame: frame, pointer: currentPointer, at: startedAt)
            mismatchSince = nil
            confirmedAt = now
            lastMetadataObservation = nil
            mode = .pointer
            return .usePointer
          }
        }
      }
      lastMetadataObservation = MetadataObservation(
        frame: frame, pointer: currentPointer, capturedAt: capturedAt)
      return .useMetadata
    }
  }

  public func predictedFrame(at pointer: CGPoint) -> CGRect? {
    mode == .pointer ? gesture.frame(at: pointer) : nil
  }

  private func pointerCandidates(near time: TimeInterval, window: TimeInterval) -> [CGPoint] {
    var points = samples.compactMap { sample in
      abs(sample.time - time) <= window ? sample.point : nil
    }
    if let interpolated = interpolatedPoint(at: time) {
      points.append(interpolated)
    }
    if points.isEmpty, let nearest = sampleNearest(to: time) {
      points.append(nearest.point)
    }
    return points
  }

  private func subframePointerCandidates() -> [CGPoint] {
    guard samples.count > 1 else { return samples.map(\.point) }
    var points: [CGPoint] = []
    points.reserveCapacity(samples.count * 2)
    for index in samples.indices {
      let current = samples[index]
      if index > 0 {
        let previous = samples[index - 1]
        let dt = current.time - previous.time
        let dx = current.point.x - previous.point.x
        let dy = current.point.y - previous.point.y
        let distance = hypot(dx, dy)
        if dt > 0, dt <= Self.maxInterpolationDeltaTime, distance > Self.interpolationStepDistance {
          let subdivisions = min(
            Self.maxInterpolationSubdivisions,
            Int(ceil(distance / Self.interpolationStepDistance)))
          if subdivisions > 1 {
            for step in 1..<subdivisions {
              let fraction = Double(step) / Double(subdivisions)
              points.append(
                CGPoint(
                  x: previous.point.x + dx * fraction,
                  y: previous.point.y + dy * fraction))
            }
          }
        }
      }
      points.append(current.point)
    }
    return points
  }

  private func interpolatedPoint(at time: TimeInterval) -> CGPoint? {
    guard !samples.isEmpty else { return nil }
    if let index = samples.firstIndex(where: { $0.time >= time }) {
      let upper = samples[index]
      guard index > 0 else { return upper.point }
      let lower = samples[index - 1]
      let dt = upper.time - lower.time
      if dt > 0, dt <= Self.maxInterpolationDeltaTime {
        let fraction = (time - lower.time) / dt
        return CGPoint(
          x: lower.point.x + (upper.point.x - lower.point.x) * fraction,
          y: lower.point.y + (upper.point.y - lower.point.y) * fraction)
      }
    }
    return sampleNearest(to: time)?.point
  }

  private func sampleNearest(to time: TimeInterval) -> Sample? {
    samples.min { abs($0.time - time) < abs($1.time - time) }
  }
}
