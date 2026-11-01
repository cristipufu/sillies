import Foundation
import SilliesModelStore
import SilliesTTS

/// Materializes vendor cache metadata from verified assets. No repository listing or lazy download.
enum KokoroPackagePreparation {
  private static let revision = "6c0750dd02ef9d981fb82f147d784a3f171755ee"
  static let relativeRoot = "kokoro-82m-coreml/ANE-v3/\(revision)/en"
  private static let voiceRows = 510
  private static let voiceColumns = 256
  private static let maximumIndexBytes = 1_048_576
  private struct IndexedFile: Encodable {
    struct Digest: Encodable { let oid: String }
    let type = "file"
    let path: String
    let size: Int64
    let lfs: Digest
  }

  static func prepare(_ configuration: TTSPreparation) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard configuration.variant == "english" else { throw TTSError.invalidRequest }
    let root = try ModelFiles.child(relativeRoot, in: configuration.directory)
    let basePrefix = relativeRoot + "/base/"
    let index = configuration.resources.filter { $0.path.hasPrefix(basePrefix) }.map {
      IndexedFile(
        path: "ANE/" + $0.path.dropFirst(basePrefix.count), size: $0.byteCount,
        lfs: .init(oid: $0.sha256))
    }
    guard !index.isEmpty else { throw TTSError.invalidRequest }
    _ = try ModelDerivedArtifact.materialize(
      .init(
        root: root, path: "base-index-v3.json",
        sources: index.map { "\($0.path):\($0.size):\($0.lfs.oid)" },
        format: .init(version: "kokoro-index-v3.1", maximumBytes: maximumIndexBytes))
    ) { try JSONEncoder().encode(index) }
  }

  static func prepareVoice(_ voice: String, configuration: TTSPreparation) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let root = try ModelFiles.child(relativeRoot, in: configuration.directory)
    let voicePrefix = relativeRoot + "/voice-sources/"
    // Some catalog voices already ship in the runtime's binary format.
    if configuration.resources.contains(where: { $0.path == relativeRoot + "/" + voice + ".bin" }) {
      return
    }
    guard
      let resource = configuration.resources.first(where: {
        $0.path == voicePrefix + voice + ".json"
      })
    else { throw TTSError.unsupportedVoice }
    let source = try ModelFiles.child(resource.path, in: configuration.directory)
    _ = try ModelDerivedArtifact.materialize(
      .init(
        root: root, path: "voices/\(voice).bin", sources: [resource.sha256],
        format: .init(
          version: "kokoro-voice-float32le.\(voiceRows)x\(voiceColumns).1",
          maximumBytes: voiceRows * voiceColumns * MemoryLayout<Float>.size))
    ) { try decodeVoice(Data(contentsOf: source)) }
  }

  private static func decodeVoice(_ data: Data) throws -> Data {
    let rows = try JSONDecoder().decode([String: [Float]].self, from: data)
    var output = Data(capacity: voiceRows * voiceColumns * MemoryLayout<Float>.size)
    for index in 1...voiceRows {
      guard let row = rows[String(index)], row.count == voiceColumns, row.allSatisfy(\.isFinite)
      else { throw TTSError.invalidAudio }
      for value in row {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { output.append(contentsOf: $0) }
      }
    }
    return output
  }
}
