import CoreGraphics
import Foundation
import WindowMetadataProtocol

/// A worker thread still shares the UI process's CG connection lock. A helper process does not.
enum WindowMetadataReader {
  private static let client = WindowMetadataClient()

  static func start(owner: ObjectIdentifier) { client.start(owner: owner) }
  static func stop(owner: ObjectIdentifier) { client.stop(owner: owner) }

  static func snapshot(
    _ options: CGWindowListOption, _ reference: CGWindowID
  ) -> WindowMetadataSnapshot? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let request = WindowMetadataRequest(options: options.rawValue, reference: reference)
    return client.read(request)
  }

  static func copyInfo(_ options: CGWindowListOption, _ reference: CGWindowID) -> [[String: Any]] {
    snapshot(options, reference)?.entries ?? []
  }
}
