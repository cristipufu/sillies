import CWoofArchive
import Foundation

/// Reads numeric NPZ members in memory. Model archives never execute code or extract filesystem paths.
struct WoofTensorArchive {
  struct Limits {
    var maximumArchiveBytes = 64 * 1_024 * 1_024
    var maximumExpandedBytes = 256 * 1_024 * 1_024
    var maximumEntries = 2_048
  }

  private enum ZIP {
    static let endSignature: UInt32 = 0x0605_4b50
    static let centralSignature: UInt32 = 0x0201_4b50
    static let localSignature: UInt32 = 0x0403_4b50
    static let endSize = 22
    static let centralSize = 46
    static let localSize = 30
    static let maximumCommentBytes = 65_535
    static let encryptedFlag: UInt16 = 1
    static let dataDescriptorFlag: UInt16 = 8
    static let utf8Flag: UInt16 = 0x0800
  }

  private struct Directory {
    let offset: Int
    let length: Int
    let count: Int
  }

  private struct Entry {
    let name: Data
    let method: UInt16
    let flags: UInt16
    let checksum: UInt32
    let compressedBytes: Int
    let expandedBytes: Int
    let localOffset: Int
    let directoryBytes: Int
  }

  private let reader: WoofByteReader
  private let limits: Limits

  init(data: Data, limits: Limits = .init()) throws {
    guard data.count <= limits.maximumArchiveBytes else { throw WoofModelError.archiveLimit }
    reader = WoofByteReader(data: data)
    self.limits = limits
  }

  func arrays() throws -> [String: WoofNumpyArray] {
    let directory = try directory()
    var offset = directory.offset
    var expandedBytes = 0
    var arrays: [String: WoofNumpyArray] = [:]
    for _ in 0..<directory.count {
      try Task.checkCancellation()
      let entry = try entry(at: offset)
      guard entry.expandedBytes <= limits.maximumExpandedBytes - expandedBytes else {
        throw WoofModelError.archiveLimit
      }
      expandedBytes += entry.expandedBytes
      let name = try arrayName(entry.name)
      guard arrays[name] == nil else { throw WoofModelError.invalidArchive }
      arrays[name] = try WoofNumpyArray(data: contents(of: entry, before: directory.offset))
      offset += entry.directoryBytes
      guard offset <= directory.offset + directory.length else {
        throw WoofModelError.invalidArchive
      }
    }
    guard offset == directory.offset + directory.length else {
      throw WoofModelError.invalidArchive
    }
    return arrays
  }

  private func directory() throws -> Directory {
    guard reader.data.count >= ZIP.endSize else { throw WoofModelError.invalidArchive }
    let lastOffset = reader.data.count - ZIP.endSize
    let firstOffset = max(0, lastOffset - ZIP.maximumCommentBytes)
    for offset in stride(from: lastOffset, through: firstOffset, by: -1) {
      guard try reader.uint32(at: offset) == ZIP.endSignature,
        Int(try reader.uint16(at: offset + 20)) == lastOffset - offset
      else { continue }
      guard try reader.uint16(at: offset + 4) == 0,
        try reader.uint16(at: offset + 6) == 0
      else { throw WoofModelError.invalidArchive }
      let count = Int(try reader.uint16(at: offset + 10))
      guard count <= limits.maximumEntries else { throw WoofModelError.archiveLimit }
      guard Int(try reader.uint16(at: offset + 8)) == count else {
        throw WoofModelError.invalidArchive
      }
      let directoryOffset = Int(try reader.uint32(at: offset + 16))
      let length = Int(try reader.uint32(at: offset + 12))
      guard directoryOffset <= offset, length == offset - directoryOffset else {
        throw WoofModelError.invalidArchive
      }
      return Directory(offset: directoryOffset, length: length, count: count)
    }
    throw WoofModelError.invalidArchive
  }

  private func entry(at offset: Int) throws -> Entry {
    guard try reader.uint32(at: offset) == ZIP.centralSignature else {
      throw WoofModelError.invalidArchive
    }
    let flags = try reader.uint16(at: offset + 8)
    let allowedFlags = ZIP.dataDescriptorFlag | ZIP.utf8Flag
    let method = try reader.uint16(at: offset + 10)
    guard flags & ~allowedFlags == 0, method == 0 || method == 8,
      try reader.uint16(at: offset + 34) == 0
    else { throw WoofModelError.invalidArchive }
    let nameBytes = Int(try reader.uint16(at: offset + 28))
    let extraBytes = Int(try reader.uint16(at: offset + 30))
    let commentBytes = Int(try reader.uint16(at: offset + 32))
    return Entry(
      name: try reader.bytes(at: offset + ZIP.centralSize, count: nameBytes), method: method,
      flags: flags, checksum: try reader.uint32(at: offset + 16),
      compressedBytes: Int(try reader.uint32(at: offset + 20)),
      expandedBytes: Int(try reader.uint32(at: offset + 24)),
      localOffset: Int(try reader.uint32(at: offset + 42)),
      directoryBytes: ZIP.centralSize + nameBytes + extraBytes + commentBytes)
  }

  private func arrayName(_ data: Data) throws -> String {
    guard let name = String(data: data, encoding: .utf8), name.hasSuffix(".npy"),
      !name.contains("/"), !name.contains("\\"), !name.contains(".."), name.count > 4
    else { throw WoofModelError.invalidArchive }
    return String(name.dropLast(4))
  }

  private func contents(of entry: Entry, before directoryOffset: Int) throws -> Data {
    let offset = entry.localOffset
    guard try reader.uint32(at: offset) == ZIP.localSignature,
      try reader.uint16(at: offset + 6) == entry.flags,
      try reader.uint16(at: offset + 8) == entry.method
    else { throw WoofModelError.invalidArchive }
    let nameBytes = Int(try reader.uint16(at: offset + 26))
    let extraBytes = Int(try reader.uint16(at: offset + 28))
    guard try reader.bytes(at: offset + ZIP.localSize, count: nameBytes) == entry.name else {
      throw WoofModelError.invalidArchive
    }
    let start = offset + ZIP.localSize + nameBytes + extraBytes
    guard start <= directoryOffset, entry.compressedBytes <= directoryOffset - start else {
      throw WoofModelError.invalidArchive
    }
    let compressed = try reader.bytes(at: start, count: entry.compressedBytes)
    let expanded = try expand(compressed, entry: entry)
    let checksum = expanded.withUnsafeBytes {
      sillies_woof_crc32($0.bindMemory(to: UInt8.self).baseAddress, $0.count)
    }
    guard checksum == entry.checksum else { throw WoofModelError.invalidArchive }
    return expanded
  }

  private func expand(_ data: Data, entry: Entry) throws -> Data {
    if entry.method == 0 {
      guard data.count == entry.expandedBytes else { throw WoofModelError.invalidArchive }
      return data
    }
    guard entry.expandedBytes > 0 else { throw WoofModelError.invalidArchive }
    var expanded = Data(count: entry.expandedBytes)
    let valid = expanded.withUnsafeMutableBytes { output in
      data.withUnsafeBytes { input in
        sillies_woof_inflate(
          input.bindMemory(to: UInt8.self).baseAddress, input.count,
          output.bindMemory(to: UInt8.self).baseAddress, output.count)
      }
    }
    guard valid != 0 else { throw WoofModelError.invalidArchive }
    return expanded
  }
}
