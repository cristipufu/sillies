import AppKit
import Observation
import SilliesWriting

/// A user-invoked picker may take focus; paste explicitly restores and revalidates its saved field.
@MainActor @Observable final class PasteBackCoordinator {
  private(set) var destination: TextDestination?
  private(set) var notice: String?
  private(set) var isPasting = false
  private let insertion: any TextInserting
  private var generation = UUID()
  init(insertion: any TextInserting = TextInsertionService()) { self.insertion = insertion }
  var actionTitle: String { destination.map { "Paste into \($0.applicationName)" } ?? "Copy text" }

  func captureDestination() async {
    guard let application = FrontmostApplication.current else { return }
    generation = UUID()
    let token = generation
    do {
      let captured = try await insertion.capture(application)
      guard generation == token, !Task.isCancelled else {
        await insertion.release(captured)
        return
      }
      destination = captured
      notice = nil
    } catch {
      guard generation == token else { return }
      destination = nil
      notice = error.localizedDescription
    }
  }

  func paste(_ text: String) async throws {
    guard !isPasting, let destination else { throw TextAccessError.unsupported }
    isPasting = true
    let token = generation
    defer {
      isPasting = false
      self.destination = nil
    }
    do {
      try await activateDestination(destination)
      guard generation == token else { throw CancellationError() }
      try await insertion.insert(text, into: destination)
    } catch {
      notice = error.localizedDescription
      await insertion.release(destination)
      throw error
    }
  }
  private func activateDestination(_ destination: TextDestination) async throws {
    guard let application = NSRunningApplication(processIdentifier: destination.processID),
      application.activate(options: [])
    else { throw TextAccessError.changed }
    // Activation is asynchronous; AX still validates the element, selected range, and context.
    for _ in 0..<10 {
      try Task.checkCancellation()
      if NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processID {
        break
      }
      try await Task.sleep(for: .milliseconds(25))
    }
  }
  func release() {
    generation = UUID()
    if let destination { Task { [insertion] in await insertion.release(destination) } }
    destination = nil
  }
}
