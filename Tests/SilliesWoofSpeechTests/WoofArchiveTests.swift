import Foundation
import Testing

@testable import SilliesWoofSpeech

struct WoofArchiveTests {
  @Test func textChunksPreserveWordsAndNormalizeTypographicPunctuation() {
    #expect(
      WoofTextPreparation.chunks("Hello! I am your little window companion.") == [
        "Hello! I am your little window companion."
      ])
    #expect(
      WoofTextPreparation.chunks("  It’s\n‘hello’ — not “goodbye”.  ") == [
        "It's 'hello' — not \"goodbye\"."
      ])
    let long = Array(repeating: "This is a sentence with several words.", count: 10).joined(
      separator: " ")
    let chunks = WoofTextPreparation.chunks(long)
    #expect(chunks.count > 1)
    #expect(chunks.allSatisfy { !$0.isEmpty && $0.count <= 120 })
    #expect(chunks.joined(separator: " ") == long)
    #expect(WoofTextPreparation.chunks(" \n\t").isEmpty)
    #expect(
      WoofTextPreparation.chunks(String(repeating: "a", count: 500)).joined()
        == String(repeating: "a", count: 500))
  }

  @Test func positionalTensorMetadataRejectsMissingAndExtraParameters() {
    for json in ["[]", "[{},{},{}]", "[{},{},{},{},{}]"] {
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(WoofSpeechLayerParameters.self, from: Data(json.utf8))
      }
    }
  }
  @Test func numpyRejectsExecutableTypesAndInvalidDimensions() throws {
    for descriptor in ["|O", ">f4", "<U99999999999999999999999"] {
      #expect(throws: WoofModelError.self) {
        try WoofNumpyArray(
          data: Self.numpy(descriptor: descriptor, shape: "(1,)", bytes: Data([0])))
      }
    }
    for shape in ["(-1,)", "(9223372036854775807, 8)", "(1, 2)"] {
      #expect(throws: WoofModelError.self) {
        try WoofNumpyArray(data: Self.numpy(descriptor: "<f4", shape: shape, bytes: Data(count: 4)))
      }
    }
  }

  @Test func numpyKeepsShapeAndExactNumericBytes() throws {
    let values = Data([1, 0, 0, 0, 2, 0, 0, 0])
    let array = try WoofNumpyArray(
      data: Self.numpy(descriptor: "<i4", shape: "(2,)", bytes: values))
    #expect(array.shape == [2])
    #expect(array.scalarType == .int32)
    #expect(array.storage == values)
    #expect(throws: WoofModelError.self) {
      try WoofNumpyArray(
        data: Self.numpy(descriptor: "<i4", shape: "(2,)", bytes: values.dropLast()))
    }
  }

  @Test func truncatedArchiveAndArchiveLimitsFailRecoverably() throws {
    #expect(throws: WoofModelError.self) {
      try WoofTensorArchive(data: Data([0x50, 0x4b])).arrays()
    }
    #expect(throws: WoofModelError.archiveLimit) {
      try WoofTensorArchive(data: Data(count: 9), limits: .init(maximumArchiveBytes: 8))
    }
    for offset in [-1, Int.max, 4] {
      #expect(throws: WoofModelError.self) {
        try WoofByteReader(data: Data(count: 4)).uint32(at: offset)
      }
    }
  }

  @Test func noiseIsReproducibleAndRejectsInvalidShapes() throws {
    var first = WoofGaussianNoise(seed: 42)
    var second = WoofGaussianNoise(seed: 42)
    for _ in 0..<50 {
      #expect(
        try first.samples(count: 32, standardDeviation: 0.5)
          == second.samples(count: 32, standardDeviation: 0.5))
    }
    #expect(throws: WoofModelError.self) { try first.samples(count: 3, standardDeviation: 1) }
    #expect(throws: WoofModelError.self) { try first.samples(count: 32, standardDeviation: .nan) }
  }

  private static func numpy(descriptor: String, shape: String, bytes: Data) -> Data {
    let header = Data(
      "{'descr': '\(descriptor)', 'fortran_order': False, 'shape': \(shape), }\n".utf8)
    var data = Data([
      0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 1, 0, UInt8(header.count & 255), UInt8(header.count >> 8),
    ])
    data.append(header)
    data.append(bytes)
    return data
  }
}
