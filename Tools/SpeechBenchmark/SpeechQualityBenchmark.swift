import AVFoundation
import CryptoKit
import Foundation
import SilliesAudio
import SilliesCore
import SilliesModelStore
import SilliesSpeech
import SilliesSpeechNemotron
import SilliesSpeechParakeet
import SilliesSpeechWhisper
import Synchronization

/// Paired file-only recognition using the same prepared native model and decoder configuration.
enum SpeechQualityBenchmark {
  private enum Limits {
    static let manifestBytes = 1_024 * 1_024
    static let audioBytes = 8 * 1_024 * 1_024
    static let fixtures = 256
    static let replaySeconds = 23.5
    static let realtimeSeconds = 90.0
    static let packetSeconds = 0.1
    static let inferenceWindows = 1_024
    static let draftBytes = 64 * 1_024
  }
  private struct Options {
    enum Feed: String, Codable { case replay, realtime }
    let model: String
    let store: URL
    let manifest: URL
    let output: URL
    let split: String
    let feed: Feed
    init(_ arguments: [String]) throws {
      guard arguments.count == 6, let feed = Feed(rawValue: arguments[5]),
        ["dev", "test"].contains(arguments[4])
      else {
        throw SpeechError.unavailable(
          "Usage: SpeechBenchmark quality MODEL STORE MANIFEST OUTPUT dev|test replay|realtime")
      }
      model = arguments[0]
      store = URL(fileURLWithPath: arguments[1], isDirectory: true)
      manifest = URL(fileURLWithPath: arguments[2])
      output = URL(fileURLWithPath: arguments[3])
      split = arguments[4]
      self.feed = feed
    }
  }
  private struct Manifest: Decodable {
    struct Fixture: Codable {
      let id: String
      let language: String
      let split: String
      let file: String
      let reference: String
      let sha256: String
      var condition: String?
    }
    let fixtures: [Fixture]
  }
  private struct Result: Codable {
    let id: String
    let language: String
    let condition: String
    let mode: SpeechBoundaryPolicy.Mode
    let reference: String
    let hypothesis: String
    let draftHypotheses: [String]
    let audioSeconds: Double
    let processingSeconds: Double
    let finalizationSeconds: Double
    let windows: [SpeechWindowMeasurement]
    let inferenceWindows: [SpeechInferenceMeasurement]
    let inferenceRequests: Int
    let decodedInputSamples: Int
    let errors: [String]
  }
  private struct Report: Encodable {
    private struct Comparison: Encodable { let kind = "end-to-end" }
    private let comparison = Comparison()
    let schema = 1
    let pipeline = "meeting-disk-backed"
    let model: String
    let revision: String
    let manifestSHA256: String
    let split: String
    let feed: Options.Feed
    let expectedResults: Int
    var results: [Result] = []
    var complete = false
    func save(to url: URL) throws {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(self).write(to: url, options: .atomic)
    }
  }
  private final class Output: Sendable {
    struct Snapshot {
      var finals: [String] = []
      var drafts: [String] = []
      var draftBytes = 0
      var errors: [String] = []
      var windows: [SpeechWindowMeasurement] = []
      var inferenceWindows: [SpeechInferenceMeasurement] = []
      var inferenceRequests = 0
      var decodedInputSamples = 0
    }
    private let state = Mutex(Snapshot())
    var snapshot: Snapshot { state.withLock { $0 } }
    func receive(_ phrase: SpeechPhrase) {
      guard !phrase.text.isEmpty else { return }
      state.withLock {
        if phrase.isFinal {
          $0.finals.append(phrase.text)
        } else if $0.drafts.count < Limits.inferenceWindows,
          phrase.text.utf8.count <= Limits.draftBytes - $0.draftBytes
        {
          $0.drafts.append(phrase.text)
          $0.draftBytes += phrase.text.utf8.count
        } else if $0.errors.isEmpty {
          $0.errors.append("Quality draft trace exceeded its bound.")
        }
      }
    }
    func fail(_ message: String) { state.withLock { $0.errors.append(message) } }
    func measure(_ event: SpeechWindowMeasurement) {
      state.withLock {
        if $0.windows.count < Limits.inferenceWindows {
          $0.windows.append(event)
        } else if $0.errors.isEmpty {
          $0.errors.append("Quality window trace exceeded its bound.")
        }
      }
    }
    func measure(_ event: SpeechInferenceMeasurement) {
      state.withLock {
        if $0.inferenceWindows.count < Limits.inferenceWindows {
          $0.inferenceWindows.append(event)
        } else if $0.errors.isEmpty {
          $0.errors.append("Quality inference trace exceeded its bound.")
        }
        $0.inferenceRequests += 1
        $0.decodedInputSamples += event.sampleCount
      }
    }
  }
  @concurrent static func run(_ arguments: [String]) async throws {
    let options = try Options(arguments)
    let manifestSize = try options.manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard (1...Limits.manifestBytes).contains(manifestSize) else {
      throw SpeechError.unavailable("Quality manifest exceeds its byte bound.")
    }
    let bytes = try Data(contentsOf: options.manifest)
    let manifest = try JSONDecoder().decode(Manifest.self, from: bytes)
    let fixtures = manifest.fixtures.filter { $0.split == options.split }
    guard !fixtures.isEmpty, manifest.fixtures.count <= Limits.fixtures,
      Set(fixtures.map(\.id)).count == fixtures.count,
      !FileManager.default.fileExists(atPath: options.output.path)
    else {
      throw SpeechError.unavailable(
        "Quality input must contain unique fixtures and a new output path.")
    }
    let specification = try SpeechModelCatalog.bundled().manifest(for: options.model)
    let store = ModelStore(root: options.store)
    let lease = try await store.acquire(specification)
    let providers: [any SpeechProvider] = [
      WhisperSpeechProvider(), ParakeetSpeechProvider(), NemotronSpeechProvider(),
    ]
    guard let provider = providers.first(where: { $0.id == specification.model.providerID }) else {
      throw SpeechError.unavailable("No quality provider registered.")
    }
    let model = try await provider.prepare(
      .init(model: specification.model, directory: lease.directory))
    if let warmup = manifest.fixtures.first(where: {
      $0.split == "dev" && ($0.condition ?? "clean") == "clean"
    }) {
      let url = try verifiedAudio(warmup, manifest: options.manifest)
      for mode in SpeechBoundaryPolicy.Mode.allCases {
        _ = try await recognize(
          .init(
            fixture: warmup, url: url, mode: mode, model: model, feed: .replay,
            backlogDirectory: options.output.deletingLastPathComponent()))
      }
      print("Both recognition policies warmed on calibration audio.")
    }
    var report = Report(
      model: options.model, revision: specification.model.revision,
      manifestSHA256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
      split: options.split, feed: options.feed, expectedResults: fixtures.count * 2)
    try report.save(to: options.output)
    for (index, fixture) in fixtures.enumerated() {
      try Task.checkCancellation()
      let url = try verifiedAudio(fixture, manifest: options.manifest)
      let modes: [SpeechBoundaryPolicy.Mode] =
        index.isMultiple(of: 2) ? [.baseline, .adaptive] : [.adaptive, .baseline]
      for mode in modes {
        let result = try await recognize(
          .init(
            fixture: fixture, url: url, mode: mode, model: model, feed: options.feed,
            backlogDirectory: options.output.deletingLastPathComponent()))
        report.results.append(result)
        try report.save(to: options.output)
        print("\(index + 1)/\(fixtures.count) \(fixture.id) \(mode.rawValue): \(result.hypothesis)")
      }
    }
    report.complete = report.results.count == report.expectedResults
    try report.save(to: options.output)
    withExtendedLifetime(lease) {}
  }
  private static func verifiedAudio(_ fixture: Manifest.Fixture, manifest: URL) throws -> URL {
    let directory = manifest.deletingLastPathComponent().resolvingSymlinksInPath()
    let url = directory.appendingPathComponent(fixture.file).resolvingSymlinksInPath()
    guard url.path.hasPrefix(directory.path + "/") else {
      throw SpeechError.unavailable("Quality audio must remain inside the manifest directory.")
    }
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard (1...Limits.audioBytes).contains(size) else {
      throw SpeechError.unavailable("Quality fixture exceeds its byte bound.")
    }
    let audio = try Data(contentsOf: url)
    guard SHA256.hash(data: audio).map({ String(format: "%02x", $0) }).joined() == fixture.sha256
    else {
      throw SpeechError.unavailable("Quality fixture checksum mismatch.")
    }
    return url
  }
  private struct Request {
    let fixture: Manifest.Fixture
    let url: URL
    let mode: SpeechBoundaryPolicy.Mode
    let model: any PreparedSpeechModel
    let feed: Options.Feed
    let backlogDirectory: URL
  }
  private static func recognize(_ request: Request) async throws -> Result {
    let file = try AVAudioFile(forReading: request.url)
    let duration = Double(file.length) / file.processingFormat.sampleRate
    guard file.processingFormat.sampleRate.isFinite,
      (8_000...384_000).contains(file.processingFormat.sampleRate),
      (1...2).contains(file.processingFormat.channelCount), duration > 0,
      duration <= (request.feed == .replay ? Limits.replaySeconds : Limits.realtimeSeconds)
    else {
      throw SpeechError.unavailable("Quality fixture exceeds its feed duration bound.")
    }
    let output = Output()
    var channelRequest = SpeechChannelRequest(
      language: .init(
        id: request.fixture.language, name: request.fixture.language, isInstalled: true),
      output: output.receive, failure: output.fail)
    channelRequest.context.purpose = .continuousTranscription
    channelRequest.context.boundaryMode = request.mode
    channelRequest.audioBackingStore = DiskSpeechAudioStore(directory: request.backlogDirectory)
    channelRequest.measureWindow = output.measure
    channelRequest.measureInference = output.measure
    let channel = try await request.model.makeChannel(channelRequest)
    defer { channel.cancel() }
    let started = ContinuousClock.now
    while file.framePosition < file.length {
      try Task.checkCancellation()
      guard
        let buffer = AVAudioPCMBuffer(
          pcmFormat: file.processingFormat,
          frameCapacity: AVAudioFrameCount(file.processingFormat.sampleRate * Limits.packetSeconds))
      else {
        throw SpeechError.unavailable("Could not allocate bounded quality packet.")
      }
      try file.read(into: buffer)
      channel.append(buffer)
      if request.feed == .realtime {
        try await Task.sleep(for: .seconds(Double(buffer.frameLength) / buffer.format.sampleRate))
      }
    }
    let released = ContinuousClock.now
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in channel.finish { continuation.resume() } }
    } onCancel: {
      channel.cancel()
    }
    try Task.checkCancellation()
    let completed = ContinuousClock.now
    let snapshot = output.snapshot
    return Result(
      id: request.fixture.id, language: request.fixture.language,
      condition: request.fixture.condition ?? "original", mode: request.mode,
      reference: request.fixture.reference,
      hypothesis: snapshot.finals.joined(separator: " "), draftHypotheses: snapshot.drafts,
      audioSeconds: duration,
      processingSeconds: seconds(started.duration(to: completed)),
      finalizationSeconds: seconds(released.duration(to: completed)),
      windows: snapshot.windows, inferenceWindows: snapshot.inferenceWindows,
      inferenceRequests: snapshot.inferenceRequests,
      decodedInputSamples: snapshot.decodedInputSamples,
      errors: snapshot.errors)
  }
  private static func seconds(_ duration: Duration) -> Double {
    let attosecondsPerSecond = 1e18
    return Double(duration.components.seconds) + Double(duration.components.attoseconds)
      / attosecondsPerSecond
  }
}
