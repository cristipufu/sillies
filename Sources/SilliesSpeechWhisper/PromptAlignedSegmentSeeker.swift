import CoreML
import Foundation
@preconcurrency import WhisperKit

/// WhisperKit 1.1.1 writes attention rows including the prompt, then reads them without it.
/// Keep this compatibility adapter until upstream issue #542 is fixed in our pinned release.
/// https://github.com/argmaxinc/argmax-oss-swift/issues/542
final class PromptAlignedSegmentSeeker: SegmentSeeking {
  private let base = SegmentSeeker()

  // These signatures are imposed by WhisperKit's adapter protocol.
  func findSeekPointAndSegments(
    decodingResult: DecodingResult, options: DecodingOptions, allSegmentsCount: Int,
    currentSeek: Int, segmentSize: Int, sampleRate: Int, timeToken: Int, specialToken: Int,
    tokenizer: WhisperTokenizer
  ) -> (Int, [TranscriptionSegment]?) {
    base.findSeekPointAndSegments(
      decodingResult: decodingResult, options: options, allSegmentsCount: allSegmentsCount,
      currentSeek: currentSeek, segmentSize: segmentSize, sampleRate: sampleRate,
      timeToken: timeToken, specialToken: specialToken, tokenizer: tokenizer)
  }

  func addWordTimestamps(
    segments: [TranscriptionSegment], alignmentWeights: MLMultiArray, tokenizer: WhisperTokenizer,
    seek: Int, segmentSize: Int, prependPunctuations: String, appendPunctuations: String,
    lastSpeechTimestamp: Float, options: DecodingOptions, timings: TranscriptionTimings
  ) throws -> [TranscriptionSegment]? {
    // Our provider caps prompts below WhisperKit's context trimming limit.
    let count = (options.promptTokens ?? []).filter {
      $0 < tokenizer.specialTokens.specialTokenBegin
    }.count
    let offset = count == 0 ? 0 : count + 1  // Include <|startofprev|>.
    let aligned = try PromptAlignmentWeights.removingPrefix(offset, from: alignmentWeights)
    guard segments.reduce(0, { $0 + $1.tokens.count }) <= aligned.shape[0].intValue else {
      throw WhisperError.segmentingFailed("Prompt alignment exceeds the decoder context.")
    }
    return try base.addWordTimestamps(
      segments: segments, alignmentWeights: aligned, tokenizer: tokenizer, seek: seek,
      segmentSize: segmentSize, prependPunctuations: prependPunctuations,
      appendPunctuations: appendPunctuations, lastSpeechTimestamp: lastSpeechTimestamp,
      options: options, timings: timings)
  }
}
