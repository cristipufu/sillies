import Foundation

/// Checked reads keep archive offsets, lengths and tensor headers outside unsafe pointer arithmetic.
struct WoofByteReader {
  let data: Data

  func bytes(at offset: Int, count: Int) throws -> Data {
    guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else {
      throw WoofModelError.invalidArchive
    }
    return data.subdata(in: offset..<(offset + count))
  }

  func uint16(at offset: Int) throws -> UInt16 {
    let bytes = try bytes(at: offset, count: 2)
    return UInt16(bytes[0]) | UInt16(bytes[1]) << 8
  }

  func uint32(at offset: Int) throws -> UInt32 {
    let bytes = try bytes(at: offset, count: 4)
    return UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16
      | UInt32(bytes[3]) << 24
  }
}
