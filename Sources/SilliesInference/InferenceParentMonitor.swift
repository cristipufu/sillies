import Darwin
import Foundation

/// A native inference call may never return. Parent death must still release the helper process.
package enum InferenceParentMonitor {
  package static func start() -> any DispatchSourceProcess {
    let parent = getppid()
    guard parent > 1 else { _exit(EXIT_SUCCESS) }
    let source = DispatchSource.makeProcessSource(
      identifier: parent, eventMask: .exit, queue: .global(qos: .utility))
    source.setEventHandler { _exit(EXIT_SUCCESS) }
    source.resume()
    // Close the race between reading the parent ID and subscribing to its exit.
    guard getppid() == parent else { _exit(EXIT_SUCCESS) }
    return source
  }
}
