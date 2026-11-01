import Foundation
import SilliesTTS

actor SampleCollector {
  private let started = ContinuousClock.now
  private var firstPCM: Duration?
  private var samples: [Float] = []
  private var sampleRate = 0
  func append(_ audio: SynthesizedAudio) {
    if firstPCM == nil { firstPCM = started.duration(to: .now) }
    sampleRate = audio.sampleRate
    samples.append(contentsOf: audio.samples)
  }
  func write(to url: URL) throws -> String {
    guard sampleRate > 0, samples.count > sampleRate / 4,
      samples.contains(where: { abs($0) > 0.001 })
    else { throw TTSError.invalidAudio }
    let dataBytes = samples.count * MemoryLayout<Int16>.size
    var data = Data("RIFF".utf8)
    func integer<T: FixedWidthInteger>(_ value: T) {
      var little = value.littleEndian
      withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    integer(UInt32(dataBytes + 36))
    data.append(Data("WAVEfmt ".utf8))
    integer(UInt32(16))
    integer(UInt16(1))
    integer(UInt16(1))
    integer(UInt32(sampleRate))
    integer(UInt32(sampleRate * 2))
    integer(UInt16(2))
    integer(UInt16(16))
    data.append(Data("data".utf8))
    integer(UInt32(dataBytes))
    for sample in samples { integer(Int16(max(-1, min(1, sample)) * Float(Int16.max))) }
    try data.write(to: url, options: .atomic)
    return
      "\(Double(samples.count) / Double(sampleRate)) seconds of valid audio → \(url.path); first PCM \(firstPCM ?? .zero)"
  }
}
