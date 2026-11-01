import AppKit
import Darwin
import Testing

/// AppKit needs the actual main thread, which Swift's async-main CLI host does not retain.
/// This host owns the native event loop until Swift Testing returns its final status.
@main @MainActor struct NativeTestHost {
  static func main() {
    let arguments = CommandLine.arguments
    guard let flag = arguments.firstIndex(of: "--test-bundle-path"),
      arguments.indices.contains(flag + 1)
    else { fail("Missing test bundle path") }
    guard dlopen(arguments[flag + 1], RTLD_NOW | RTLD_GLOBAL) != nil else {
      fail(dlerror().map { String(cString: $0) } ?? "Could not load the test bundle")
    }
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    Task {
      let status: CInt = await Testing.__swiftPMEntryPoint()
      exit(status)
    }
    application.run()
    fail("The native event loop stopped before Swift Testing completed")
  }

  private static func fail(_ message: String) -> Never {
    fputs("Native test host: \(message)\n", stderr)
    exit(EXIT_FAILURE)
  }
}
