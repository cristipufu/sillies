import Foundation

/// The model's NumPy files contain plain numeric buffers and one UTF-32 JSON tree, never pickle.
struct WoofNumpyArray {
  enum ScalarType: Equatable {
    case int8, uint8, int32, int64, float16, float32
    case unicode(Int)

    var byteWidth: Int {
      switch self {
      case .int8, .uint8: 1
      case .float16: 2
      case .int32, .float32: 4
      case .int64: 8
      case .unicode(let count): count * 4
      }
    }
  }

  private static let maximumHeaderBytes = 65_536
  private static let maximumDimensions = 8
  private static let maximumUnicodeScalars = 1_048_576
  private static let signature = Data([0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59])
  let scalarType: ScalarType
  let shape: [Int]
  let storage: Data

  init(data: Data) throws {
    let reader = WoofByteReader(data: data)
    guard try reader.bytes(at: 0, count: 6) == Self.signature else {
      throw WoofModelError.invalidArray
    }
    let version = try reader.uint16(at: 6)
    let headerStart: Int
    let headerBytes: Int
    switch version {
    case 1:
      headerStart = 10
      headerBytes = Int(try reader.uint16(at: 8))
    case 2, 3:
      headerStart = 12
      headerBytes = Int(try reader.uint32(at: 8))
    default: throw WoofModelError.invalidArray
    }
    guard headerBytes <= Self.maximumHeaderBytes,
      let header = String(
        data: try reader.bytes(at: headerStart, count: headerBytes), encoding: .utf8),
      header.hasSuffix("\n"),
      try Self.field(#"['"]fortran_order['"]\s*:\s*(True|False)"#, in: header) == "False"
    else { throw WoofModelError.invalidArray }
    scalarType = try Self.scalarType(
      Self.field(#"['"]descr['"]\s*:\s*['"]([^'"]+)['"]"#, in: header))
    shape = try Self.dimensions(
      Self.field(#"['"]shape['"]\s*:\s*\(([^)]*)\)"#, in: header))
    var expectedBytes = scalarType.byteWidth
    for dimension in shape {
      let product = expectedBytes.multipliedReportingOverflow(by: dimension)
      guard !product.overflow else { throw WoofModelError.invalidArray }
      expectedBytes = product.partialValue
    }
    let start = headerStart + headerBytes
    guard start <= data.count, expectedBytes == data.count - start else {
      throw WoofModelError.invalidArray
    }
    storage = try reader.bytes(at: start, count: expectedBytes)
  }

  func unicodeString() throws -> String {
    guard case .unicode = scalarType, shape.isEmpty else { throw WoofModelError.invalidArray }
    let reader = WoofByteReader(data: storage)
    var scalars = String.UnicodeScalarView()
    for offset in stride(from: 0, to: storage.count, by: 4) {
      let value = try reader.uint32(at: offset)
      guard let scalar = Unicode.Scalar(value) else { throw WoofModelError.invalidArray }
      scalars.append(scalar)
    }
    return String(scalars)
  }

  private static func field(_ pattern: String, in header: String) throws -> String {
    let expression = try NSRegularExpression(pattern: pattern)
    let range = NSRange(header.startIndex..<header.endIndex, in: header)
    guard let match = expression.firstMatch(in: header, range: range),
      let value = Range(match.range(at: 1), in: header)
    else { throw WoofModelError.invalidArray }
    return String(header[value])
  }

  private static func dimensions(_ text: String) throws -> [Int] {
    let values = text.split(separator: ",", omittingEmptySubsequences: false)
    guard values.count <= maximumDimensions + 1 else { throw WoofModelError.invalidArray }
    var dimensions: [Int] = []
    for (index, value) in values.enumerated() {
      let trimmed = value.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty, index == values.count - 1 { continue }
      guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }),
        let dimension = Int(trimmed), dimension >= 0
      else { throw WoofModelError.invalidArray }
      dimensions.append(dimension)
    }
    guard dimensions.count <= maximumDimensions else { throw WoofModelError.invalidArray }
    return dimensions
  }

  private static func scalarType(_ descriptor: String) throws -> ScalarType {
    switch descriptor {
    case "|i1", "<i1": return .int8
    case "|u1", "<u1": return .uint8
    case "<i4": return .int32
    case "<i8": return .int64
    case "<f2": return .float16
    case "<f4": return .float32
    default:
      guard descriptor.hasPrefix("<U"), let count = Int(descriptor.dropFirst(2)),
        count > 0, count <= maximumUnicodeScalars
      else { throw WoofModelError.unsupportedArrayType }
      return .unicode(count)
    }
  }
}
