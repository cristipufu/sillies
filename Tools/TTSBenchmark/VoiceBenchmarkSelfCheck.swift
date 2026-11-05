import Foundation
import SilliesTTS
import SilliesTextModels

/// Independent known-sample checks keep measurement failures separate from model failures.
enum VoiceBenchmarkSelfCheck {
  private static let knownSampleSHA256 =
    "2dc6ad64a41cf5fa205222c306fccc1e62685dd486a3923bcff6657587119f4e"

  static func run() async throws {
    let origin = ProcessInfo.processInfo.systemUptime - 2
    let samples = VoiceProfileSamples(delivery: .drain, startedAt: origin)
    let first = Float(bitPattern: 0x3dcc_cccd)
    let second = Float(bitPattern: 0xbe4c_cccd)
    try await samples.append(.init(samples: [first], sampleRate: 24_000))
    try await samples.append(.init(samples: [second], sampleRate: 24_000))
    let report = await samples.report()
    guard report.startedAt == origin, report.chunks.count == 2,
      report.chunks[0].arrived >= 2,
      report.sampleCount == 2, report.pcmSHA256 == knownSampleSHA256,
      report.elapsedSeconds >= report.chunks[1].accepted
    else { throw TTSError.unavailable("Voice sample timing or original PCM hashing failed.") }

    let combined = VoiceProfileSamples(delivery: .drain)
    try await combined.append(.init(samples: [first, second], sampleRate: 24_000))
    guard await combined.report().pcmSHA256 == knownSampleSHA256 else {
      throw TTSError.unavailable("PCM hashes depend on transport chunk boundaries.")
    }
    let changed = VoiceProfileSamples(delivery: .drain)
    try await changed.append(.init(samples: [first.nextUp, second], sampleRate: 24_000))
    guard await changed.report().pcmSHA256 != knownSampleSHA256 else {
      throw TTSError.unavailable("PCM hashing lost sub-Int16 differences.")
    }
    try await checkTextEvidence()
    try VoiceConversationBenchmark.validateDelivery("One. Two!", phrases: ["One.", "Two!"])
    do {
      try VoiceConversationBenchmark.validateDelivery("One. Two!", phrases: ["One.", "One."])
      throw TextModelError.invalidResponse
    } catch TTSError.unavailable {}
    print("Voice benchmark timing, Float32 evidence and streamed-text validation: passed")
  }

  private static func checkTextEvidence() async throws {
    let timing = VoiceOverlapTiming(started: ProcessInfo.processInfo.systemUptime)
    guard await timing.received("Hello"), await !timing.received(" there") else {
      throw TextModelError.invalidResponse
    }
    do {
      try await timing.finished("Different words")
      throw TTSError.unavailable("The overlap probe accepted mismatched streamed text.")
    } catch TextModelError.invalidResponse {}
    guard await timing.completed == nil else { throw TextModelError.invalidResponse }
    try await timing.finished("Hello there")
    guard let first = await timing.first, let completed = await timing.completed,
      completed >= first
    else { throw TextModelError.invalidResponse }
  }
}
