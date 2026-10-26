import AppKit
import SilliesCore

struct DragWindowRegion: Sendable {
  let windowID: UInt32
  var frame: CGRect
}

/// A front-to-back metadata snapshot per gesture. Moving the pointer performs no WindowServer IPC.
@MainActor
final class DragWindowSnapshot {
  typealias Loader = @Sendable (Double) async -> [DragWindowRegion]
  private let load: Loader
  private var regions: [DragWindowRegion] = []
  private var recentFrames: [UInt32: (frame: CGRect, updatedAt: TimeInterval)] = [:]
  private var task: Task<Void, Never>?
  private var refreshPending = false
  private var active = false
  private var generation = 0
  var onChange: (() -> Void)?

  init(load: @escaping Loader = { await WindowTargetMetadata.shared.regions(primaryScreenTop: $0) })
  {
    self.load = load
  }

  func start(seed: WindowTargetCandidate?) {
    stop()
    active = true
    if let seed { regions = [DragWindowRegion(windowID: seed.windowID, frame: seed.frame)] }
    refresh()
  }

  func stop() {
    generation += 1
    active = false
    task?.cancel()
    task = nil
    regions.removeAll(keepingCapacity: true)
    recentFrames.removeAll(keepingCapacity: true)
    refreshPending = false
  }

  func refresh() {
    guard active else { return }
    guard task == nil else {
      refreshPending = true
      return
    }
    let token = generation
    let started = ProcessInfo.processInfo.systemUptime
    let top = Double(NSScreen.screens.first?.frame.maxY ?? 0)
    let loader = load
    task = Task { [weak self] in
      var loaded = await loader(top)
      guard !Task.isCancelled, let self, self.generation == token, self.active else { return }
      self.task = nil
      for (id, update) in self.recentFrames where update.updatedAt > started {
        if let index = loaded.firstIndex(where: { $0.windowID == id }) {
          loaded[index].frame = update.frame
        } else {
          loaded.insert(DragWindowRegion(windowID: id, frame: update.frame), at: 0)
        }
      }
      self.regions = loaded
      self.onChange?()
      if self.refreshPending {
        self.refreshPending = false
        self.refresh()
      }
    }
  }

  func updateKnownWindow(_ id: UInt32?, frame: CGRect?) {
    guard active, let id, let frame else { return }
    if let index = regions.firstIndex(where: { $0.windowID == id }) {
      guard regions[index].frame != frame else { return }
      regions[index].frame = frame
    } else {
      regions.insert(DragWindowRegion(windowID: id, frame: frame), at: 0)
      refresh()
    }
    recentFrames[id] = (frame, ProcessInfo.processInfo.systemUptime)
    onChange?()
  }

  func hitTest(at point: CGPoint, below windowNumber: Int) -> Int {
    let start =
      windowNumber == 0
      ? 0
      : (regions.firstIndex(where: { Int($0.windowID) == windowNumber }).map { $0 + 1 }
        ?? regions.count)
    return regions.dropFirst(start).first(where: { $0.frame.contains(point) }).map {
      Int($0.windowID)
    } ?? 0
  }
}
