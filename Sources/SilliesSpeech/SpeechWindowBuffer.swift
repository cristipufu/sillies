import Accelerate
import Foundation

/// Keeps only the current utterance and a short overlap, independent of session length.
struct SpeechWindowBuffer {
  enum Mode { case live, draining }
  enum Completion { case draft, boundary, utterance, session }
  struct Window {
    let samples: [Float]
    let start: TimeInterval
    let completion: Completion
    var end: TimeInterval { start + Double(samples.count) / sampleRate }
  }
  static let sampleRate: Double = 16_000
  static let maximumWindowDuration: TimeInterval = 12
  static let maximumBufferedDuration: TimeInterval = 24
  private static let draftInterval: TimeInterval = 2
  private static let silenceDuration: TimeInterval = 0.6
  private static let leadingContext: TimeInterval = 0.2
  private static let speechThreshold: Float = 0.002
  private(set) var samples: [Float] = []
  private var startSample: Int64 = 0
  private var lastDecodedCount = 0
  private var silentSamples = 0
  private var hasSpeech = false
  private var lastSpeechEndSample: Int64 = 0
  private var utteranceEnds: [Int64] = []

  mutating func append(_ incoming: [Float]) throws {
    guard !incoming.isEmpty else { return }
    guard samples.count + incoming.count <= Int(Self.maximumBufferedDuration * Self.sampleRate)
    else { throw SpeechError.overloaded }
    samples.append(contentsOf: incoming)
    if vDSP.rootMeanSquare(incoming) > Self.speechThreshold {
      hasSpeech = true
      silentSamples = 0
      lastSpeechEndSample = startSample + Int64(samples.count)
    } else {
      let wasSilent = silentSamples >= Int(Self.silenceDuration * Self.sampleRate)
      silentSamples += incoming.count
      if hasSpeech, !wasSilent, silentSamples >= Int(Self.silenceDuration * Self.sampleRate) {
        utteranceEnds.append(startSample + Int64(samples.count))
      }
    }
  }

  mutating func next(mode: Mode) -> Window? {
    guard !samples.isEmpty else { return nil }
    if !hasSpeech {
      discard(
        samples.count
          - (mode == .draining ? 0 : min(samples.count, Int(Self.leadingContext * Self.sampleRate)))
      )
      return nil
    }
    let maximum = Int(Self.maximumWindowDuration * Self.sampleRate)
    let completion: Completion
    let endpoint = utteranceEnds.first.map { Int($0 - startSample) }
    if let endpoint, endpoint <= maximum {
      completion = .utterance
    } else if samples.count >= maximum {
      completion = .boundary
    } else if mode == .draining {
      completion = .session
    } else if samples.count - lastDecodedCount >= Int(Self.draftInterval * Self.sampleRate) {
      completion = .draft
    } else {
      return nil
    }
    let count = min(maximum, samples.count, endpoint ?? samples.count)
    lastDecodedCount = count
    return Window(
      samples: Array(samples.prefix(count)), start: Double(startSample) / Self.sampleRate,
      completion: completion)
  }

  mutating func retire(_ window: Window, through boundary: TimeInterval) {
    guard window.completion != .draft else { return }
    let retireTime =
      window.completion == .boundary
      ? max(window.start, boundary - Self.leadingContext) : window.end
    let count = max(
      0, min(samples.count, Int((retireTime * Self.sampleRate).rounded()) - Int(startSample)))
    discard(count)
    hasSpeech = lastSpeechEndSample > startSample
  }

  mutating func clear() {
    samples.removeAll()
    hasSpeech = false
    utteranceEnds.removeAll()
  }

  private mutating func discard(_ count: Int) {
    guard count > 0 else { return }
    samples.removeFirst(count)
    startSample += Int64(count)
    utteranceEnds.removeAll { $0 <= startSample }
    lastDecodedCount = max(0, lastDecodedCount - count)
    silentSamples = min(silentSamples, samples.count)
  }
}
