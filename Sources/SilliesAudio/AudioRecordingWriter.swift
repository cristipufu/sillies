import AVFoundation
import Foundation
import SilliesSpeech

/// Confined to the audio worker. A completed file is published only after its AAC container closes.
final class AudioRecordingWriter {
  private static let sampleRate = 48_000.0
  private static let channelCount: AVAudioChannelCount = 1
  private static let bitRate = 96_000
  let destination: URL
  private let temporaryURL: URL
  private var file: AVAudioFile?
  private let converter: SpeechBufferConverter
  private(set) var framesWritten: AVAudioFramePosition = 0

  init(destination: URL) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    self.destination = destination
    temporaryURL = destination.deletingPathExtension().appendingPathExtension("partial.m4a")
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    guard
      let format = AVAudioFormat(
        standardFormatWithSampleRate: Self.sampleRate, channels: Self.channelCount)
    else {
      throw AudioCaptureFailure.unavailable("The recording format is unavailable.")
    }
    converter = SpeechBufferConverter(format: format)
    file = try AVAudioFile(
      forWriting: temporaryURL,
      settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: Self.sampleRate,
        AVNumberOfChannelsKey: Self.channelCount, AVEncoderBitRateKey: Self.bitRate,
      ])
  }

  func append(_ buffer: AVAudioPCMBuffer) throws {
    let converted = try converter.convert(buffer)
    try file?.write(from: converted)
    framesWritten += AVAudioFramePosition(converted.frameLength)
  }

  func finish() throws -> URL? {
    file = nil
    guard framesWritten > 0 else {
      try FileManager.default.removeItem(at: temporaryURL)
      return nil
    }
    try FileManager.default.moveItem(at: temporaryURL, to: destination)
    return destination
  }
}
