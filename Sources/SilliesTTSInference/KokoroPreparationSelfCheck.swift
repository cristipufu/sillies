import Foundation
import SilliesModelStore
import SilliesTTS

/// Offline regression for binary catalog voices and lazily converted JSON voices.
enum KokoroPreparationSelfCheck {
  static func run() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try ModelFiles.createDirectory(root)
    defer {
      do { try FileManager.default.removeItem(at: root) } catch {
        fputs("Kokoro preparation fixture cleanup failed: \(error.localizedDescription)\n", stderr)
      }
    }
    let prefix = KokoroPackagePreparation.relativeRoot
    let configuration = TTSPreparation(
      directory: root, providerID: "kokoro", variant: "english",
      resources: [
        .init(path: prefix + "/af_heart.bin", byteCount: 0, sha256: "binary-fixture"),
        .init(path: prefix + "/voice-sources/af_sky.json", byteCount: 0, sha256: "json-fixture"),
      ])
    // This voice has no JSON source: preparation must leave the verified binary alone.
    try KokoroPackagePreparation.prepareVoice("af_heart", configuration: configuration)
    guard
      let resource = configuration.resources.first(where: {
        $0.path.hasSuffix("voice-sources/af_sky.json")
      })
    else { throw TTSError.invalidRequest }
    let source = try ModelFiles.child(resource.path, in: root)
    try ModelFiles.createDirectory(source.deletingLastPathComponent())
    let rows = Dictionary(
      uniqueKeysWithValues: (1...510).map {
        (String($0), Array(repeating: Float(0.25), count: 256))
      })
    try ModelFiles.write(rows, to: source)
    try KokoroPackagePreparation.prepareVoice("af_sky", configuration: configuration)
    let output = source.deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("voices/af_sky.bin")
    let first = try Data(contentsOf: output)
    var expected = Data()
    for _ in 0..<(510 * 256) { expected.append(contentsOf: [0, 0, 128, 62]) }
    guard first == expected else { throw TTSError.invalidAudio }
    let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
    try KokoroPackagePreparation.prepareVoice("af_sky", configuration: configuration)
    let repeated = try FileManager.default.attributesOfItem(atPath: output.path)
    guard attributes[.modificationDate] as? Date == repeated[.modificationDate] as? Date else {
      throw TTSError.invalidAudio
    }
  }
}
