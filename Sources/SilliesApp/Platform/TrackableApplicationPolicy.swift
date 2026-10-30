import AppKit

enum TrackableApplicationPolicy {
  private static let systemCoreServicesPrefix = "/System/Library/CoreServices/"
  private static let systemFrameworksPrefix = "/System/Library/Frameworks/"
  private static let systemPrivateFrameworksPrefix = "/System/Library/PrivateFrameworks/"
  private static let allowedSystemBundleIdentifiers: Set<String> = [
    "com.apple.finder"
  ]

  static func isTrackable(_ application: NSRunningApplication) -> Bool {
    isTrackable(
      activationPolicy: application.activationPolicy,
      bundleIdentifier: application.bundleIdentifier,
      bundlePath: application.bundleURL?.path)
  }

  static func isTrackable(
    activationPolicy: NSApplication.ActivationPolicy,
    bundleIdentifier: String?,
    bundlePath: String?
  ) -> Bool {
    guard activationPolicy == .regular else { return false }
    if let bundleIdentifier, allowedSystemBundleIdentifiers.contains(bundleIdentifier) {
      return true
    }
    if let bundlePath {
      if bundlePath.hasPrefix(systemCoreServicesPrefix)
        || bundlePath.hasPrefix(systemFrameworksPrefix)
        || bundlePath.hasPrefix(systemPrivateFrameworksPrefix)
      {
        return false
      }
    }
    return true
  }
}
