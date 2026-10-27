import AVFoundation
import Foundation
import SilliesCore
import Testing

@testable import SilliesApp

private struct EchoFixtureNoise {
  var state: UInt64
  var previous: Float = 0
  mutating func next() -> Float {
    state = state &* 6_364_136_223_846_793_005 &+ 1
    let white = Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max)
    previous = 0.65 * previous + 0.35 * white
    return previous * 0.3
  }
}

@Test func echoCancellerReducesDelayedSpeakerEchoAndPreservesDoubleTalk() async throws {
  try await Task.detached {
    let canceller = try MeetingEchoCanceller()
    let rate = MeetingAudioTimeline.sampleRate
    let count = rate * 12
    let delay = rate / 20
    var farNoise = EchoFixtureNoise(state: 42)
    var nearNoise = EchoFixtureNoise(state: 71)
    let reference = (0..<count).map { _ in farNoise.next() }
    let near = (0..<count).map { $0 >= rate * 8 ? nearNoise.next() : Float.zero }
    let microphone = (0..<count).map { index in
      near[index] + (index >= delay ? reference[index - delay] * 0.6 : 0)
        + (index >= delay * 2 ? reference[index - delay * 2] * 0.2 : 0)
    }
    var cleaned: [Float] = []
    for start in stride(from: 0, to: count, by: MeetingAudioTimeline.frameSamples) {
      let range = start..<(start + MeetingAudioTimeline.frameSamples)
      cleaned += try canceller.process(
        reference: Array(reference[range]), microphone: Array(microphone[range]))
    }
    func energy(_ samples: ArraySlice<Float>) -> Double {
      samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count)
    }
    let echoRange = (rate * 5)..<(rate * 8)
    let attenuation =
      10 * log10(energy(microphone[echoRange]) / max(energy(cleaned[echoRange]), 1e-12))
    let speechRange = (rate * 9)..<count
    let nearGain = energy(cleaned[speechRange]) / energy(near[speechRange])
    print(
      "AEC: echo reduction \(attenuation) dB; simultaneous near speech energy ratio \(nearGain)")
    #expect(attenuation > 20)
    #expect(nearGain > 0.3 && nearGain < 1.5)
    // Preserve the near speaker's waveform, allowing the AEC's bounded block latency.
    let bestCorrelation =
      (0...160).map { lag -> Double in
        let range = (rate * 9)..<(count - 160)
        var product = 0.0
        var inputEnergy = 0.0
        var outputEnergy = 0.0
        for index in range {
          let input = Double(near[index])
          let output = Double(cleaned[index + lag])
          product += input * output
          inputEnergy += input * input
          outputEnergy += output * output
        }
        return product / sqrt(max(inputEnergy * outputEnergy, 1e-12))
      }.max() ?? 0
    print("AEC: near speech correlation \(bestCorrelation)")
    #expect(bestCorrelation > 0.75)
    try canceller.reset()
    let silence = [Float](repeating: 0, count: MeetingAudioTimeline.frameSamples)
    #expect(try canceller.process(reference: silence, microphone: silence).allSatisfy(\.isFinite))
  }.value
}
