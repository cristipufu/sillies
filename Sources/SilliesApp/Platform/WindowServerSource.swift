import CoreGraphics
import Foundation
import SilliesCore

struct WindowServerObservation: Sendable {
  let processID: pid_t
  let windowID: CGWindowID?
  let frame: CGRect?
  let capturedAt: TimeInterval
  var backgroundWindowIDs: Set<Int>?
  var inputWindowFrames: [Int: CGRect]?
}

/// Public window metadata only. No images, window titles, or screen-capture permission.
/// Discovery is infrequent; manipulation reads are restricted to one known window.
final class WindowServerSource: @unchecked Sendable {
  private struct Request {
    let processID: pid_t
    let windowID: CGWindowID?
    let discover: Bool
  }

  private static let minimumVisibleAlpha: Double = 0.05

  private let queue = DispatchQueue(label: "app.sillies.window-geometry", qos: .userInteractive)
  private let lock = NSLock()
  private var pending = false
  private var queued: Request?
  private let deliver: @Sendable (WindowServerObservation) -> Void

  init(deliver: @escaping @Sendable (WindowServerObservation) -> Void) { self.deliver = deliver }

  func refresh(processID: pid_t, windowID: CGWindowID?, discover: Bool) {
    lock.lock()
    if pending {
      let mergedDiscover =
        (queued?.processID == processID ? (queued?.discover ?? false) : false) || discover
      queued = Request(processID: processID, windowID: windowID, discover: mergedDiscover)
      lock.unlock()
      return
    }
    pending = true
    lock.unlock()
    enqueue(Request(processID: processID, windowID: windowID, discover: discover))
  }

  private func enqueue(_ request: Request) {
    queue.async { [self] in
      performRefresh(request)
      lock.lock()
      if let next = queued {
        queued = nil
        lock.unlock()
        enqueue(next)
      } else {
        pending = false
        lock.unlock()
      }
    }
  }

  private func performRefresh(_ request: Request) {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let processID = request.processID
    let windowID = request.windowID
    let discover = request.discover
    let options: CGWindowListOption =
      discover || windowID == nil
      ? [.optionOnScreenOnly] : [.optionIncludingWindow]
    let reference = discover ? kCGNullWindowID : (windowID ?? kCGNullWindowID)
    let capturedAt = ProcessInfo.processInfo.systemUptime
    let entries = CGWindowListCopyWindowInfo(options, reference) as? [[String: Any]] ?? []
    let backgroundIDs: Set<Int>? =
      discover || windowID == nil
      ? Set(
        entries.compactMap { row in
          guard (row[kCGWindowLayer as String] as? Int ?? 0) < 0 else { return nil }
          return row[kCGWindowNumber as String] as? Int
        }) : nil
    let inputFrames: [Int: CGRect]? =
      discover || windowID == nil
      ? Dictionary(
        uniqueKeysWithValues: entries.compactMap { row in
          guard (row[kCGWindowLayer as String] as? Int ?? -1) >= 0,
            let id = row[kCGWindowNumber as String] as? Int,
            let bounds = row[kCGWindowBounds as String] as? [String: Any],
            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
          else { return nil }
          return (id, frame)
        }) : nil
    let minimumSize = PointerWindowGesture.defaultMinimumWindowSize
    for entry in entries {
      guard (entry[kCGWindowOwnerPID as String] as? Int32) == processID,
        (entry[kCGWindowLayer as String] as? Int) == 0,
        (entry[kCGWindowIsOnscreen as String] as? Bool) != false,
        (entry[kCGWindowAlpha as String] as? Double ?? 1) > Self.minimumVisibleAlpha,
        let id = entry[kCGWindowNumber as String] as? UInt32,
        let bounds = entry[kCGWindowBounds as String] as? [String: Any],
        let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
        frame.width >= minimumSize.width, frame.height >= minimumSize.height
      else { continue }
      deliver(
        WindowServerObservation(
          processID: processID, windowID: id, frame: frame, capturedAt: capturedAt,
          backgroundWindowIDs: backgroundIDs, inputWindowFrames: inputFrames))
      return
    }
    deliver(
      WindowServerObservation(
        processID: processID, windowID: nil, frame: nil, capturedAt: capturedAt,
        backgroundWindowIDs: backgroundIDs, inputWindowFrames: inputFrames))
  }
}
