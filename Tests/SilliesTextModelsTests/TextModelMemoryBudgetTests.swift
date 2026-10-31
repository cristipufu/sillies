import Testing

@testable import SilliesTextModels

@Test func textModelMemoryAdmissionSupportsLargeWeightsWithoutConsumingTheWholeMac() throws {
  let gib = TextModelMemoryBudget.gibibyte
  let allocation = try TextModelMemoryBudget.allocation(
    weightBytes: 15_400_000_000, physicalMemory: UInt64(32 * gib))
  #expect(allocation > 12 * gib)
  #expect(allocation < 22 * gib)
  #expect(throws: (any Error).self) {
    try TextModelMemoryBudget.allocation(
      weightBytes: 15_400_000_000, physicalMemory: UInt64(16 * gib))
  }
  #expect(
    try TextModelMemoryBudget.allocation(
      weightBytes: 1_750_000_000, physicalMemory: UInt64(8 * gib)) < 4 * gib)
}

@Test func textModelMemoryAdmissionRejectsMalformedAndOverflowingSizes() {
  for bytes: Int64 in [-1, 0, .max] {
    #expect(throws: (any Error).self) {
      try TextModelMemoryBudget.allocation(weightBytes: bytes, physicalMemory: .max)
    }
  }
}
