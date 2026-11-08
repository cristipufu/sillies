import Foundation

/// The model's published sampling recipe uses MT19937 and a 16-value Box–Muller layout.
/// Keeping the generator local makes parallel helpers and seeded comparisons independent.
struct WoofGaussianNoise {
  private static let stateCount = 624
  private static let twistOffset = 397
  private static let initializationMultiplier: UInt32 = 1_812_433_253
  private static let twistMask: UInt32 = 0x9908_b0df
  private var state: [UInt32]
  private var position = Self.stateCount

  init(seed: UInt32) {
    state = Array(repeating: 0, count: Self.stateCount)
    state[0] = seed
    for index in 1..<Self.stateCount {
      let previous = state[index - 1]
      state[index] = Self.initializationMultiplier &* (previous ^ (previous >> 30)) &+ UInt32(index)
    }
  }

  mutating func samples(count: Int, standardDeviation: Float) throws -> [Float] {
    guard count > 0, count.isMultiple(of: 16), count <= 128,
      standardDeviation.isFinite, standardDeviation >= 0
    else { throw WoofModelError.invalidConfiguration }
    let uniforms = (0..<count).map { _ in Double(next() & 0x00ff_ffff) / 16_777_216 }
    var result = Array(repeating: Float.zero, count: count)
    for block in stride(from: 0, to: count, by: 16) {
      for pair in 0..<8 {
        let radius = sqrt(-2 * log(1 - uniforms[block + pair]))
        let angle = 2 * Double.pi * uniforms[block + pair + 8]
        result[block + pair] = Float(radius * cos(angle)) * standardDeviation
        result[block + pair + 8] = Float(radius * sin(angle)) * standardDeviation
      }
    }
    return result
  }

  private mutating func next() -> UInt32 {
    if position == Self.stateCount { twist() }
    var value = state[position]
    position += 1
    value ^= value >> 11
    value ^= (value << 7) & 0x9d2c_5680
    value ^= (value << 15) & 0xefc6_0000
    value ^= value >> 18
    return value
  }

  private mutating func twist() {
    for index in state.indices {
      let next = (index + 1) % Self.stateCount
      let combined = (state[index] & 0x8000_0000) | (state[next] & 0x7fff_ffff)
      let source = (index + Self.twistOffset) % Self.stateCount
      state[index] = state[source] ^ (combined >> 1)
      if combined & 1 != 0 { state[index] ^= Self.twistMask }
    }
    position = 0
  }
}
