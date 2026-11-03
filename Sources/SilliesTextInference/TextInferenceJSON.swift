import Foundation
import SilliesTextModels

/// Bounded local metadata reads shared by inference configuration and explicit diagnostics.
enum TextInferenceJSON {
  static func read<Value: Decodable>(
    _ type: Value.Type, from url: URL, maximumBytes: Int
  ) throws -> Value {
    guard maximumBytes > 0, maximumBytes < Int.max else { throw TextModelError.invalidResponse }
    let file = try FileHandle(forReadingFrom: url)
    defer {
      do { try file.close() } catch { fputs("Cannot close inference metadata: \(error)\n", stderr) }
    }
    let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
    guard data.count <= maximumBytes else { throw TextModelError.invalidResponse }
    return try JSONDecoder().decode(type, from: data)
  }

  static func readIfPresent<Value: Decodable>(
    _ type: Value.Type, from url: URL, maximumBytes: Int
  ) throws -> Value? {
    do { return try read(type, from: url, maximumBytes: maximumBytes) } catch let error
      as CocoaError
      where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
    {
      return nil
    }
  }
}
