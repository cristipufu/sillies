import AppKit
import QuartzCore
import Testing

@testable import SilliesApp

@Test @MainActor
func metadataProcessReadsExactWindowAndStopsWithItsLastOwner() async throws {
  let window = NSWindow(
    contentRect: CGRect(x: 140, y: 140, width: 600, height: 400),
    styleMask: [.titled], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.alphaValue = 0.01
  window.orderFrontRegardless()
  // The helper cannot see the test process's uncommitted native-window transaction.
  CATransaction.flush()
  defer { window.close() }
  let id = UInt32(window.windowNumber)
  let client = WindowMetadataClient()
  let firstOwner = NSObject()
  let secondOwner = NSObject()
  let firstID = ObjectIdentifier(firstOwner)
  let secondID = ObjectIdentifier(secondOwner)
  client.start(owner: firstID)
  client.start(owner: secondID)
  defer {
    client.stop(owner: firstID)
    client.stop(owner: secondID)
  }

  let returnedIDs = await Task.detached {
    client.read(.init(options: CGWindowListOption.optionIncludingWindow.rawValue, reference: id))?
      .entries.compactMap { $0[kCGWindowNumber as String] as? UInt32 }
  }.value
  #expect(returnedIDs == [id])
  let helperPID = try #require(client.processIdentifier)
  #expect(helperPID != ProcessInfo.processInfo.processIdentifier)
  client.stop(owner: firstID)
  #expect(client.processIdentifier == helperPID)
  client.stop(owner: secondID)
  #expect(client.processIdentifier == nil)
  let stoppedRead = await Task.detached {
    client.read(.init(options: CGWindowListOption.optionIncludingWindow.rawValue, reference: id))
      == nil
  }.value
  #expect(stoppedRead)
  let deadline = ProcessInfo.processInfo.systemUptime + 2
  while kill(helperPID, 0) == 0, ProcessInfo.processInfo.systemUptime < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(kill(helperPID, 0) == -1)
}

@Test @MainActor
func metadataProcessRecoversAfterItsPipeCloses() async throws {
  let client = WindowMetadataClient()
  let owner = NSObject()
  let ownerID = ObjectIdentifier(owner)
  client.start(owner: ownerID)
  defer { client.stop(owner: ownerID) }
  let firstReply = await Task.detached {
    client.read(.init(options: CGWindowListOption.optionOnScreenOnly.rawValue, reference: 0)) != nil
  }.value
  #expect(firstReply)
  let firstPID = try #require(client.processIdentifier)
  #expect(kill(firstPID, SIGKILL) == 0)
  let deadline = ProcessInfo.processInfo.systemUptime + 2
  while kill(firstPID, 0) == 0, ProcessInfo.processInfo.systemUptime < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
  // The broken pipe must fail on its worker without SIGPIPE killing the UI process.
  let interruptedReply = await Task.detached {
    client.read(.init(options: CGWindowListOption.optionOnScreenOnly.rawValue, reference: 0)) != nil
  }.value
  #expect(!interruptedReply)
  let recoveredReply = await Task.detached {
    client.read(.init(options: CGWindowListOption.optionOnScreenOnly.rawValue, reference: 0)) != nil
  }.value
  #expect(recoveredReply)
  #expect(client.processIdentifier != firstPID)
}
