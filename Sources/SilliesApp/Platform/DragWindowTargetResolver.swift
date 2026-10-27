import AppKit
import SilliesCore

/// Native hit testing stays immediate. Metadata is cached, coalesced, and read by a serial worker.
@MainActor
final class DragWindowTargetResolver {
  typealias HitTest = @MainActor (CGPoint, Int) -> Int
  typealias Lookup = @Sendable (UInt32, Double) async -> WindowTargetCandidate?

  struct DropTarget: Sendable {
    let windowID: UInt32
    let primaryTop: Double
    let cached: WindowTargetCandidate?
  }

  private struct Entry {
    let target: WindowTargetCandidate?
    let capturedAt: TimeInterval
  }
  private struct Request {
    let point: CGPoint
    let excluded: Set<Int>
    let primaryTop: Double
  }
  private struct NativeProbe {
    let point: CGPoint
    let excluded: Set<Int>
    let number: Int?
    let capturedAt: TimeInterval
  }
  private static let nativeProbeInterval: TimeInterval = 1.0 / 60
  private static let nativeProbeTravel: Double = 12
  private static let refreshInterval: TimeInterval = 15.0
  private static let maxCacheEntries = 32
  private static let maxStackDepth = 16
  private let hitTest: HitTest
  private let dropHitTest: HitTest
  private let lookup: Lookup
  private var cache: [Int: Entry] = [:]
  private var seededWindowID: Int?
  private var latest: Request?
  private var nativeProbe: NativeProbe?
  private var inFlight: Task<Void, Never>?
  private var generation = 0
  private var active = false
  private(set) var currentTarget: WindowTargetCandidate?
  var onTargetChanged: ((WindowTargetCandidate?) -> Void)?

  init(
    hitTest: @escaping HitTest = { NSWindow.windowNumber(at: $0, belowWindowWithWindowNumber: $1) },
    dropHitTest: HitTest? = nil,
    lookup: @escaping Lookup = { id, top in
      await WindowTargetMetadata.shared.candidate(for: id, primaryScreenTop: top)
    }
  ) {
    self.hitTest = hitTest
    self.dropHitTest = dropHitTest ?? hitTest
    self.lookup = lookup
  }

  func start(seed: WindowTargetCandidate? = nil) {
    stop()
    cache.removeAll(keepingCapacity: true)
    if let seed {
      let id = Int(seed.windowID)
      seededWindowID = id
      cache[id] = Entry(
        target: seed, capturedAt: ProcessInfo.processInfo.systemUptime)
    } else {
      seededWindowID = nil
    }
    active = true
  }

  func stop() {
    generation += 1
    active = false
    seededWindowID = nil
    latest = nil
    nativeProbe = nil
    inFlight?.cancel()
    inFlight = nil
    publish(nil)
  }

  func update(at point: CGPoint, excluding excluded: Set<Int>) {
    guard active else { return }
    let request = Request(
      point: point, excluded: excluded, primaryTop: Double(NSScreen.screens.first?.frame.maxY ?? 0))
    latest = request
    guard let id = candidateNumber(for: request) else {
      publish(nil)
      return
    }
    let entry = cache[id]
    if let target = entry?.target, target.frame.contains(point) {
      publish(target)
    } else {
      publish(nil)
    }
    if let entry, ProcessInfo.processInfo.systemUptime - entry.capturedAt < Self.refreshInterval {
      return
    }
    guard inFlight == nil else { return }
    let token = generation
    let load = lookup
    inFlight = Task { [weak self] in
      let result = await load(UInt32(id), request.primaryTop)
      guard !Task.isCancelled, let self, self.generation == token, self.active else { return }
      self.inFlight = nil
      if self.cache.count >= Self.maxCacheEntries { self.cache.removeAll(keepingCapacity: true) }
      self.cache[id] = Entry(target: result, capturedAt: ProcessInfo.processInfo.systemUptime)
      // Worker replies and mouse-up always get a fresh native hit test.
      self.nativeProbe = nil
      if let latest = self.latest { self.update(at: latest.point, excluding: latest.excluded) }
    }
  }

  func updateKnownWindow(_ id: UInt32?, frame: CGRect?) {
    guard active, let id, let frame else { return }
    let key = Int(id)
    if let existing = cache[key], var target = existing.target, target.frame != frame {
      target.frame = frame
      cache[key] = Entry(target: target, capturedAt: existing.capturedAt)
    }
  }

  func invalidateWindowStack() {
    nativeProbe = nil
    if inFlight == nil, let latest {
      update(at: latest.point, excluding: latest.excluded)
    }
  }

  func cachedTarget(at point: CGPoint, excluding excluded: Set<Int>) -> WindowTargetCandidate? {
    dropTarget(at: point, excluding: excluded)?.cached
  }

  func dropTarget(at point: CGPoint, excluding excluded: Set<Int>) -> DropTarget? {
    nativeProbe = nil
    let request = Request(
      point: point, excluded: excluded, primaryTop: Double(NSScreen.screens.first?.frame.maxY ?? 0))
    let now = ProcessInfo.processInfo.systemUptime
    guard
      let id = firstEligibleWindowNumber(
        at: point, excluding: excluded, using: dropHitTest, now: now)
    else { return nil }
    let cached = cache[id].flatMap { entry -> WindowTargetCandidate? in
      guard now - entry.capturedAt < Self.refreshInterval,
        let target = entry.target,
        target.frame.contains(point),
        currentTarget == nil || currentTarget?.windowID == target.windowID
      else { return nil }
      return target
    }
    return DropTarget(windowID: UInt32(id), primaryTop: request.primaryTop, cached: cached)
  }

  /// A quick drop can precede the hover lookup. Finish that lookup asynchronously after landing.
  func resolveDrop(_ request: DropTarget) async -> WindowTargetCandidate? {
    guard !Task.isCancelled else { return nil }
    if let cached = request.cached { return cached }
    // Capture the ID at mouse-up; a later hit test could otherwise select a different app.
    let result = await lookup(request.windowID, request.primaryTop)
    guard !Task.isCancelled, result?.windowID == request.windowID else { return nil }
    return result
  }

  private func candidateNumber(for request: Request) -> Int? {
    let time = ProcessInfo.processInfo.systemUptime
    if let probe = nativeProbe,
      time - probe.capturedAt < Self.nativeProbeInterval,
      probe.excluded == request.excluded,
      hypot(probe.point.x - request.point.x, probe.point.y - request.point.y)
        < Self.nativeProbeTravel
    {
      let leftKnownFrame =
        probe.number.flatMap { cache[$0]?.target }.map {
          !$0.frame.contains(request.point)
        } ?? false
      if !leftKnownFrame { return probe.number }
    }
    let result = firstEligibleWindowNumber(
      at: request.point, excluding: request.excluded, using: hitTest, now: time)
    nativeProbe = NativeProbe(
      point: request.point, excluded: request.excluded, number: result, capturedAt: time)
    return result
  }

  private func firstEligibleWindowNumber(
    at point: CGPoint,
    excluding excluded: Set<Int>,
    using hitTester: HitTest,
    now: TimeInterval
  ) -> Int? {
    var below = 0
    for _ in 0..<Self.maxStackDepth {
      let id = hitTester(point, below)
      guard id > 0, id != below else { break }
      let isKnownInvalid =
        cache[id].map {
          $0.target == nil && now - $0.capturedAt < Self.refreshInterval
        } ?? false
      if !excluded.contains(id), !isKnownInvalid {
        return id
      }
      below = id
    }
    return nil
  }

  private func publish(_ target: WindowTargetCandidate?) {
    guard currentTarget != target else { return }
    currentTarget = target
    onTargetChanged?(target)
  }
}
