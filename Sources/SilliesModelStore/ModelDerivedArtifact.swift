import CryptoKit
import Foundation
import SilliesFileSystem

/// Rebuildable local data, keyed by verified source identities and the conversion format.
/// This cache is never evidence that downloaded model weights were verified.
package enum ModelDerivedArtifact {
  package struct Format {
    package let version: String
    package let maximumBytes: Int
    package init(version: String, maximumBytes: Int) {
      self.version = version
      self.maximumBytes = maximumBytes
    }
  }
  package struct Request {
    package let root: URL
    package let path: String
    package let sources: [String]
    package let format: Format
    var maximumBytes: Int { format.maximumBytes }
    package init(root: URL, path: String, sources: [String], format: Format) {
      self.root = root
      self.path = path
      self.sources = sources
      self.format = format
    }
  }
  private struct Receipt: Codable {
    let input: String
    let format: String
    let output: String
    let byteCount: Int
  }
  private static let maximumReceiptBytes = 4_096

  package static func materialize(_ request: Request, create: () throws -> Data) throws -> URL {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    guard request.maximumBytes > 0 else { throw ModelStoreError.invalidManifest }
    let output = try ModelFiles.child(request.path, in: request.root)
    let receipt = try ModelFiles.child(request.path + ".cache.json", in: request.root)
    let input = digest(try JSONEncoder().encode(request.sources))
    if try reusable(request, output: output, receipt: receipt, input: input) { return output }
    try Task.checkCancellation()
    let data = try create()
    guard !data.isEmpty, data.count <= request.maximumBytes else {
      throw ModelStoreError.invalidManifest
    }
    try ModelFiles.createDirectory(output.deletingLastPathComponent())
    try ModelFiles.write(data: data, to: output)
    try ModelFiles.write(
      Receipt(
        input: input, format: request.format.version, output: digest(data), byteCount: data.count),
      to: receipt)
    return output
  }

  private static func reusable(_ request: Request, output: URL, receipt: URL, input: String) throws
    -> Bool
  {
    guard let encoded = try read(receipt, maximumBytes: maximumReceiptBytes) else { return false }
    let saved: Receipt
    do { saved = try JSONDecoder().decode(Receipt.self, from: encoded) } catch {
      fputs(
        "Derived model cache metadata is invalid; rebuilding: \(error.localizedDescription)\n",
        stderr)
      return false
    }
    guard saved.input == input, saved.format == request.format.version,
      saved.byteCount > 0, saved.byteCount <= request.maximumBytes,
      let data = try read(output, maximumBytes: request.maximumBytes)
    else { return false }
    return data.count == saved.byteCount && digest(data) == saved.output
  }

  private static func read(_ url: URL, maximumBytes: Int) throws -> Data? {
    do {
      return try RegularFileReader.withFile(at: url) { file in
        guard try file.fingerprint().size <= maximumBytes else { return nil }
        var result = Data()
        while let chunk = try file.readChunk(), !chunk.isEmpty {
          try Task.checkCancellation()
          guard chunk.count <= maximumBytes - result.count else { return nil }
          result.append(chunk)
        }
        return result
      }
    } catch let error as POSIXError where error.code == .ENOENT { return nil }
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
