import AppKit
import Foundation
import SilliesAudio
import SilliesCore

/// A bundle-scoped HAL inventory may represent helpers; a second app instance makes it ambiguous.
enum NativeApplicationAudioIdentity {
  static func verify(_ target: WindowTargetCandidate) -> ApplicationAudioIdentity {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard target.processID > 0, target.processID != ProcessInfo.processInfo.processIdentifier,
      let application = NSRunningApplication(processIdentifier: target.processID),
      !application.isTerminated
    else { return .unavailable }
    guard let bundle = target.bundleIdentifier, !bundle.isEmpty else { return .ambiguous }
    guard application.bundleIdentifier == bundle else { return .unavailable }
    let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
    guard applications.count == 1, applications.first?.processIdentifier == target.processID else {
      return .ambiguous
    }
    return .verified
  }
}
