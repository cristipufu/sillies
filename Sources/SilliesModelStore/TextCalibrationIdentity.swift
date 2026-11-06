import Foundation
import SilliesCore
import SilliesFileSystem

/// No serial number, host name, user name or path is part of a portable runtime identity.
package struct TextCalibrationIdentity: Codable, Equatable, Sendable {
  package struct Hardware: Codable, Equatable, Sendable {
    package let processor: String
    package let memoryBytes: UInt64
    package let operatingSystem: String
  }
  package let modelID: String
  package let revision: String
  package let profile: TextModelProfile
  package let helperSHA256: String
  package let hardware: Hardware

  package static func capture(_ manifest: TextModelManifest, helper: URL) throws -> Self {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let digest = try RegularFileReader.withFile(at: helper, ModelFileDigest.sha256)
    return try .init(
      modelID: manifest.modelID, revision: manifest.revision,
      profile: manifest.model.profile, helperSHA256: digest,
      hardware: .init(
        processor: processor(), memoryBytes: ProcessInfo.processInfo.physicalMemory,
        operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString))
  }

  private static func processor() throws -> String {
    var size = 0
    guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0,
      size > 1, size <= 256
    else { throw ModelStoreError.invalidManifest }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else {
      throw ModelStoreError.invalidManifest
    }
    return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }
}
