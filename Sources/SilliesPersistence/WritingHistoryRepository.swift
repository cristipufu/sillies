import Foundation
import SilliesCore

public struct WritingHistoryRepository: Sendable {
  private static let filename = "history.json"
  private let files: VaultFileStorage
  public init(directory: URL) { files = VaultFileStorage(directory: directory) }
  public func load() throws -> [WritingResult] {
    let data: Data
    do { data = try Data(contentsOf: files.url(for: Self.filename)) } catch CocoaError
      .fileReadNoSuchFile
    { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode([WritingResult].self, from: data)
  }
  public func save(_ results: [WritingResult]) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try files.write(encoder.encode(results), named: Self.filename)
  }
}
