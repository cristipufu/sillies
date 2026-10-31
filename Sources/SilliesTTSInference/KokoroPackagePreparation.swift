import Foundation
import SilliesModelStore
import SilliesTTS

/// Materializes vendor cache metadata from verified assets. No repository listing or lazy download.
enum KokoroPackagePreparation {
  private static let revision = "6c0750dd02ef9d981fb82f147d784a3f171755ee"
  private static let voiceRows = 510
  private static let voiceColumns = 256
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
    let relativeRoot = "kokoro-82m-coreml/ANE-v3/\(revision)/en"
    let root = try ModelFiles.child(relativeRoot, in: configuration.directory)
    let basePrefix = relativeRoot + "/base/"
    let index = configuration.resources.filter { $0.path.hasPrefix(basePrefix) }.map {
      IndexedFile(
        path: "ANE/" + $0.path.dropFirst(basePrefix.count), size: $0.byteCount,
        lfs: .init(oid: $0.sha256))
    }
    guard !index.isEmpty else { throw TTSError.invalidRequest }
    try ModelFiles.write(index, to: ModelFiles.child("base-index-v3.json", in: root))
    let voicePrefix = relativeRoot + "/voice-sources/"
    for resource in configuration.resources where resource.path.hasPrefix(voicePrefix) {
      let source = try ModelFiles.child(resource.path, in: configuration.directory)
      let name = source.deletingPathExtension().lastPathComponent
      let destination = try ModelFiles.child("voices/\(name).bin", in: root)
      try ModelFiles.createDirectory(destination.deletingLastPathComponent())
      try decodeVoice(Data(contentsOf: source)).write(to: destination, options: .atomic)
    }
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
