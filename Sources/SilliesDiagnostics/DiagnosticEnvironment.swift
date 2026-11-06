import Foundation

package struct DiagnosticEnvironment: Codable, Sendable {
  package let version: String?
  package let build: String?
  package let revision: String?
  package let builtAt: String?
  package let operatingSystem: String
  package let architecture: String
  package let memoryBytes: UInt64

  package init(bundle: Bundle = .main) {
    version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
      .flatMap(DiagnosticEvent.identifier)
    build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
      .flatMap(DiagnosticEvent.identifier)
    revision = (bundle.object(forInfoDictionaryKey: "SilliesBuildRevision") as? String)
      .flatMap(DiagnosticEvent.identifier)
    builtAt = (bundle.object(forInfoDictionaryKey: "SilliesBuildTimestamp") as? String)
      .flatMap(DiagnosticEvent.identifier)
    let system = ProcessInfo.processInfo.operatingSystemVersion
    operatingSystem = "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
    #if arch(arm64)
      architecture = "arm64"
    #else
      architecture = "x86_64"
    #endif
    memoryBytes = ProcessInfo.processInfo.physicalMemory
  }
}
