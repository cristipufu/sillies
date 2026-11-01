import Foundation

/// A real one-pixel PNG attachment; the text-only agent reads the scenario's synthetic OCR text.
enum BenchmarkImageFixture {
  private static let pixel =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a8ksAAAAASUVORK5CYII="

  static func write(to destination: URL) throws {
    guard let data = Data(base64Encoded: pixel) else { throw CocoaError(.fileReadCorruptFile) }
    try data.write(to: destination, options: .atomic)
  }
}
