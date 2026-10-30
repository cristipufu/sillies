import Foundation

/// Owns the workspace's scheduled work. Replacing or stopping a slot invalidates its old callback.
@MainActor
final class WindowTrackingSchedule {
  enum Slot: Hashable {
    case heartbeat, housekeeping, settle, transition
    case discovery(Int)
  }
  struct Repetition {
    let interval: TimeInterval
    let tolerance: TimeInterval
    var mode: RunLoop.Mode = .common
  }
  private struct Entry {
    let id: UUID
    let timer: Timer
  }
  private var entries: [Slot: Entry] = [:]
  var pendingCount: Int { entries.count }

  isolated deinit { for entry in entries.values { entry.timer.invalidate() } }

  func contains(_ slot: Slot) -> Bool { entries[slot] != nil }

  func once(_ slot: Slot, after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
    cancel(slot)
    let id = UUID()
    let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.entries[slot]?.id == id else { return }
        self.entries.removeValue(forKey: slot)
        action()
      }
    }
    entries[slot] = Entry(id: id, timer: timer)
    RunLoop.main.add(timer, forMode: .common)
  }

  func repeating(_ slot: Slot, cadence: Repetition, action: @escaping @MainActor () -> Void) {
    cancel(slot)
    let id = UUID()
    let timer = Timer(timeInterval: cadence.interval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard self?.entries[slot]?.id == id else { return }
        action()
      }
    }
    timer.tolerance = cadence.tolerance
    entries[slot] = Entry(id: id, timer: timer)
    RunLoop.main.add(timer, forMode: cadence.mode)
  }

  func cancel(_ slot: Slot) { entries.removeValue(forKey: slot)?.timer.invalidate() }

  func cancelDiscoveries() {
    for slot in Array(entries.keys) {
      if case .discovery = slot { cancel(slot) }
    }
  }

  func stop() {
    for entry in entries.values { entry.timer.invalidate() }
    entries.removeAll()
  }
}
