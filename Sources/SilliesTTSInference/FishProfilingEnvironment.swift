import Foundation
import SilliesFishSpeech
import SilliesTTS

enum FishProfilingEnvironment {
  static func configuration() throws -> FishProfileConfiguration? {
    let environment = ProcessInfo.processInfo.environment
    guard let directory = environment["SILLIES_FISH_PROFILE_DIRECTORY"] else { return nil }
    guard directory.hasPrefix("/"),
      let mode = FishProfileConfiguration.Mode(
        rawValue: environment["SILLIES_FISH_PROFILE_MODE"] ?? "natural"),
      let seed = UInt64(environment["SILLIES_FISH_PROFILE_SEED"] ?? "123")
    else { throw TTSError.invalidRequest }
    return .init(directory: URL(fileURLWithPath: directory), mode: mode, seed: seed)
  }
}
