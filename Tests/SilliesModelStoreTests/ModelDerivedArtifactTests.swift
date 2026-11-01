import Foundation
import Testing

@testable import SilliesModelStore

@Test func derivedArtifactsReuseOnlyMatchingInputsAndIntactOutput() async throws {
  try await Task.detached {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
    }
    var builds = 0
    func materialize(source: String = "source-a", format: String = "format-a") throws -> URL {
      try ModelDerivedArtifact.materialize(
        .init(
          root: root, path: "voice.bin", sources: [source],
          format: .init(version: format, maximumBytes: 8))
      ) {
        builds += 1
        return Data("voice".utf8)
      }
    }
    let output = try materialize()
    _ = try materialize()
    #expect(builds == 1)
    try Data("wrong".utf8).write(to: output)
    _ = try materialize()
    #expect(builds == 2)
    #expect(try Data(contentsOf: output) == Data("voice".utf8))
    _ = try materialize(source: "source-b")
    _ = try materialize(source: "source-b", format: "format-b")
    #expect(builds == 4)
    try Data("bad metadata".utf8).write(to: output.appendingPathExtension("cache.json"))
    _ = try materialize(source: "source-b", format: "format-b")
    #expect(builds == 5)
    try FileManager.default.removeItem(at: output)
    _ = try materialize(source: "source-b", format: "format-b")
    #expect(builds == 6)
  }.value
}

@Test func derivedArtifactsRejectSymlinksAndOversizeConversions() async throws {
  try await Task.detached {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
      do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
    }
    let target = root.appendingPathComponent("target")
    try Data("unchanged".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("voice.bin"), withDestinationURL: target)
    let request = ModelDerivedArtifact.Request(
      root: root, path: "voice.bin", sources: ["source"],
      format: .init(version: "v1", maximumBytes: 4))
    #expect(throws: ModelStoreError.self) {
      try ModelDerivedArtifact.materialize(request) { Data("test".utf8) }
    }
    #expect(try Data(contentsOf: target) == Data("unchanged".utf8))
    try FileManager.default.removeItem(at: root.appendingPathComponent("voice.bin"))
    #expect(throws: ModelStoreError.self) {
      try ModelDerivedArtifact.materialize(request) { Data("too large".utf8) }
    }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("voice.bin").path))
  }.value
}
