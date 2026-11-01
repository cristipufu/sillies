import CryptoKit
import Foundation
import SilliesFileSystem

enum ModelFileDigest {
  static func sha256(_ file: RegularFileReader) throws -> String {
    var hash = SHA256()
    while let data = try file.readChunk(), !data.isEmpty {
      try Task.checkCancellation()
      hash.update(data: data)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
