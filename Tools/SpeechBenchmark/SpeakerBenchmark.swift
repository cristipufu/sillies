import Foundation
import SilliesCore
import SilliesDiarizationNemotron
import SilliesSpeech
import Synchronization

enum SpeakerBenchmark {
  @concurrent static func run(model: SpeechModelDescriptor, directory: URL, files: [String])
    async throws
  {
    let start = ContinuousClock.now
    let prepared = try await NemotronDiarizationProvider().prepare(
      .init(model: model, directory: directory))
    print(
      "Prepared speaker detection in \(start.duration(to: .now)); footprint \(ProcessFootprint.description())"
    )
    for path in files {
      let output = SpeakerBenchmarkOutput()
      let channel = try await prepared.makeChannel(
        .init(output: output.receive, failure: output.fail))
      defer { channel.cancel() }
      let started = ContinuousClock.now
      let duration = try await BenchmarkAudio.feed(URL(fileURLWithPath: path), to: [channel])
        .duration
      try output.report(duration: duration)
      print(
        "Diarization elapsed \(started.duration(to: .now)); footprint \(ProcessFootprint.description())"
      )
    }
  }
}

private final class SpeakerBenchmarkOutput: Sendable {
  private struct State {
    var timeline = SpeakerActivityTimeline()
    var failure: String?
  }
  private let state = Mutex(State())
  func receive(_ batch: SpeakerActivityBatch) {
    state.withLock { state in
      do { try state.timeline.append(batch) } catch { state.failure = String(describing: error) }
    }
  }
  func fail(_ message: String) { state.withLock { $0.failure = message } }
  func report(duration: TimeInterval) throws {
    try state.withLock { state in
      if let failure = state.failure { throw SpeechError.unavailable(failure) }
      for start in stride(from: 0.0, to: duration, by: 1.0) {
        print("\(start)s: \(state.timeline.speaker(in: start..<min(start + 1, duration)).label)")
      }
      print("Retained activity frames: \(state.timeline.retainedFrameCount)")
    }
  }
}
