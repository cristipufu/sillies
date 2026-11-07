import CVectorSearch
import Foundation
import SilliesPersistence

/// The native handle never leaves its serialized helper runtime.
final class NativeVectorIndex {
  private static let errorCapacity = 512
  private let handle: OpaquePointer
  let dimensions: Int

  init(dimensions: Int, partitions: Int, training: VaultVectorBatch, backing: URL) throws {
    guard let dimension = Int32(exactly: dimensions), (1...4096).contains(dimensions),
      let partitionCount = Int32(exactly: partitions), (0...256).contains(partitions),
      training.ids.count <= 32_768, training.values.count == training.ids.count * dimensions
    else { throw CocoaError(.coderInvalidValue) }
    var message = [CChar](repeating: 0, count: Self.errorCapacity)
    let result = backing.path.withCString { path in
      training.values.withUnsafeBufferPointer { values in
        svi_create(
          dimension, partitionCount, values.baseAddress, training.ids.count, path, &message,
          message.count)
      }
    }
    guard let result else { throw NativeVectorError(messageBuffer: message) }
    handle = result
    self.dimensions = dimensions
  }

  init(opening path: URL, dimensions: Int) throws {
    guard let dimension = Int32(exactly: dimensions), (1...4096).contains(dimensions) else {
      throw CocoaError(.coderInvalidValue)
    }
    var message = [CChar](repeating: 0, count: Self.errorCapacity)
    let result = path.path.withCString { svi_open($0, dimension, &message, message.count) }
    guard let result else { throw NativeVectorError(messageBuffer: message) }
    handle = result
    self.dimensions = dimensions
  }

  func add(_ batch: VaultVectorBatch) throws {
    guard !batch.ids.isEmpty else { return }
    guard batch.values.count == batch.ids.count * dimensions else {
      throw CocoaError(.fileReadCorruptFile)
    }
    try perform { message in
      batch.ids.withUnsafeBufferPointer { ids in
        batch.values.withUnsafeBufferPointer { values in
          svi_add(handle, ids.baseAddress, values.baseAddress, ids.count, &message, message.count)
        }
      }
    }
  }

  func remove(_ ids: [Int64]) throws {
    guard !ids.isEmpty else { return }
    try perform { message in
      ids.withUnsafeBufferPointer {
        svi_remove(handle, $0.baseAddress, $0.count, &message, message.count)
      }
    }
  }

  func search(_ vector: [Float], limit: Int) throws -> [Int64] {
    guard vector.count == dimensions, (1...256).contains(limit) else {
      throw CocoaError(.coderInvalidValue)
    }
    var ids = [Int64](repeating: -1, count: limit)
    var scores = [Float](repeating: 0, count: limit)
    try perform { message in
      vector.withUnsafeBufferPointer {
        svi_search(handle, $0.baseAddress, limit, &ids, &scores, &message, message.count)
      }
    }
    return ids.filter { $0 > 0 }
  }

  func checkpoint(to path: URL) throws {
    try perform { message in
      path.path.withCString { svi_checkpoint(handle, $0, &message, message.count) }
    }
  }

  private func perform(_ operation: (inout [CChar]) -> Int32) throws {
    var message = [CChar](repeating: 0, count: Self.errorCapacity)
    guard operation(&message) == 1 else {
      throw NativeVectorError(messageBuffer: message)
    }
  }
  deinit { svi_close(handle) }
}
