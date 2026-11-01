import Foundation
import SilliesTTS

/// A silent sink with an optional playback-rate queue; it never opens an audio device.
actor VoiceProfileSamples {
  enum Delivery: String, Codable { case drain, paced }
  struct Chunk: Codable {
    let arrived: TimeInterval
    let accepted: TimeInterval
    let samples: Int
  }
  struct Report: Codable {
    let startedAt: TimeInterval
    let elapsedSeconds: TimeInterval
    let sampleRate: Int
    let sampleCount: Int
    let firstNonSilentPCM: TimeInterval?
    let leadingSilentSamples: Int?
    let simulatedPlaybackGapSeconds: TimeInterval
    let sinkWaitSeconds: TimeInterval
    let chunks: [Chunk]
  }
  private static let maximumQueueSeconds: TimeInterval = 0.75
  private static let minimumSignal: Float = 0.001
  private let delivery: Delivery
  private let started = ProcessInfo.processInfo.systemUptime
  private let audio = SampleCollector()
  private var chunks: [Chunk] = []
  private var sampleRate = 0
  private var sampleCount = 0
  private var firstNonSilent: TimeInterval?
  private var leadingSilentSamples: Int?
  private var playbackEnd: TimeInterval?
  private var gapSeconds: TimeInterval = 0
  private var waitSeconds: TimeInterval = 0

  init(delivery: Delivery) { self.delivery = delivery }

  func append(_ pcm: SynthesizedAudio) async throws {
    let arrived = elapsed()
    let duration = Double(pcm.samples.count) / Double(pcm.sampleRate)
    if delivery == .paced, let playbackEnd {
      let wait = max(0, playbackEnd + duration - elapsed() - Self.maximumQueueSeconds)
      if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
    }
    let accepted = elapsed()
    waitSeconds += accepted - arrived
    if let playbackEnd { gapSeconds += max(0, accepted - playbackEnd) }
    playbackEnd = max(playbackEnd ?? accepted, accepted) + duration
    if firstNonSilent == nil,
      let first = pcm.samples.firstIndex(where: { abs($0) >= Self.minimumSignal })
    {
      firstNonSilent = arrived
      leadingSilentSamples = sampleCount + first
    }
    sampleRate = pcm.sampleRate
    sampleCount += pcm.samples.count
    chunks.append(.init(arrived: arrived, accepted: accepted, samples: pcm.samples.count))
    await audio.append(pcm)
  }

  func report() -> Report {
    .init(
      startedAt: started, elapsedSeconds: elapsed(), sampleRate: sampleRate,
      sampleCount: sampleCount, firstNonSilentPCM: firstNonSilent,
      leadingSilentSamples: leadingSilentSamples,
      simulatedPlaybackGapSeconds: gapSeconds, sinkWaitSeconds: waitSeconds, chunks: chunks)
  }
  func writeAudio(to url: URL) async throws { _ = try await audio.write(to: url) }
  private func elapsed() -> TimeInterval { ProcessInfo.processInfo.systemUptime - started }
}
