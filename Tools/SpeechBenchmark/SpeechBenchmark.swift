import AVFoundation
import Foundation
import SilliesAudio
import SilliesCore
import SilliesModelStore
import SilliesSpeech
import SilliesSpeechApple
import SilliesSpeechNemotron
import SilliesSpeechParakeet
import SilliesSpeechWhisper
import Synchronization

/// Opt-in prerecorded checks. Never opens microphones or captures application audio.
@main
struct SpeechBenchmark {
  static func main() async {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      if arguments.first == "quality" {
        try await SpeechQualityBenchmark.run(Array(arguments.dropFirst()))
      } else {
        try await BenchmarkRunner().run(arguments)
      }
    } catch {
      fputs("Speech benchmark: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }
}

private actor BenchmarkRunner {
  private enum Mode { case meeting, dictation }
  func run(_ arguments: [String]) async throws {
    guard arguments.count >= 3 else {
      throw SpeechError.unavailable(
        "Usage: SpeechBenchmark install|prepare|run|dictate MODEL_ID STORE_DIRECTORY [AUDIO_FILE ...]"
      )
    }
    let command = arguments[0]
    if arguments[1] == "apple", command == "dictate" || command == "run" {
      let model = AppleSpeechProvider()
      let catalog = try await model.languages(.init(model: .apple, availability: .installed))
      guard let language = catalog.installedLanguage(matching: "en-US") else {
        throw SpeechError.unavailable("English Apple speech assets are not installed.")
      }
      for path in arguments.dropFirst(3) {
        try await exercise(
          model, file: URL(fileURLWithPath: path),
          mode: command == "dictate" ? .dictation : .meeting, language: language)
      }
      return
    }
    let manifest = try SpeechModelCatalog.bundled().manifest(for: arguments[1])
    let store = ModelStore(root: URL(fileURLWithPath: arguments[2], isDirectory: true))
    if command == "check" {
      let current = try await store.currentManifest(manifest)
      if let candidate = try await ModelUpdateDiscovery().candidate(for: current) {
        print("Update available: \(candidate.model.revision), \(candidate.downloadBytes) bytes")
      } else {
        print("No changed model artifacts for \(current.model.name).")
      }
      return
    }
    if command == "install" {
      try await store.install(manifest) { progress in
        if progress.phase == .verifying {
          print("Verified \(progress.completedBytes)/\(progress.totalBytes) bytes")
        }
      }
      print("Installed \(manifest.model.id) @ \(manifest.model.revision)")
      return
    }
    guard command == "prepare" || command == "run" || command == "dictate" else {
      throw SpeechError.unavailable("Unknown benchmark command.")
    }
    if manifest.model.isDiarizationModel {
      let lease = try await store.acquire(manifest)
      try await SpeakerBenchmark.run(
        model: manifest.model, directory: lease.directory, files: Array(arguments.dropFirst(3)))
      withExtendedLifetime(lease) {}
      return
    }
    let providers: [any SpeechProvider] = [
      WhisperSpeechProvider(), ParakeetSpeechProvider(), NemotronSpeechProvider(),
    ]
    guard let provider = providers.first(where: { $0.id == manifest.model.providerID }) else {
      throw SpeechError.unavailable("No provider registered.")
    }
    let lease = try await store.acquire(manifest)
    let started = ContinuousClock.now
    let model = try await provider.prepare(.init(model: manifest.model, directory: lease.directory))
    print(
      "Prepared \(manifest.model.id) in \(started.duration(to: .now)); process footprint \(ProcessFootprint.description())"
    )
    if command == "run" || command == "dictate" {
      guard arguments.count > 3 else {
        throw SpeechError.unavailable("Supply at least one prerecorded audio file.")
      }
      for path in arguments.dropFirst(3) {
        try await exercise(
          model, file: URL(fileURLWithPath: path),
          mode: command == "dictate" ? .dictation : .meeting,
          language: ProcessInfo.processInfo.environment["SILLIES_SPEECH_LANGUAGE"].map {
            SpeechLanguage(id: $0, name: $0, isInstalled: true)
          } ?? .automatic)
      }
    }
    withExtendedLifetime(lease) {}
  }

  private func exercise(
    _ model: any PreparedSpeechModel, file url: URL, mode: Mode,
    language: SpeechLanguage
  ) async throws {
    let outputs = (0..<(mode == .dictation ? 1 : 2)).map { _ in BenchmarkOutput() }
    var channels: [any LocalSpeechChannel] = []
    for output in outputs {
      var request = SpeechChannelRequest(
        language: language, output: output.receive, failure: output.fail)
      if mode == .dictation {
        request.context = .init(vocabulary: ["Alex", "Ștefan", "API_v2"], priority: .interactive)
      } else {
        request.context.purpose = .continuousTranscription
        request.audioBackingStore = DiskSpeechAudioStore(
          directory: FileManager.default.temporaryDirectory)
      }
      let channelStarted = ContinuousClock.now
      channels.append(try await model.makeChannel(request))
      print("Channel ready in \(channelStarted.duration(to: .now))")
    }
    defer { for channel in channels { channel.cancel() } }
    let probe = MainActorProbe()
    let probeTask = Task { await probe.measure() }
    defer { probeTask.cancel() }
    let started = ContinuousClock.now
    let timing = try await BenchmarkAudio.feed(url, to: channels)
    let latency = await probe.percentile95
    print("Process footprint after fixture: \(ProcessFootprint.description())")
    print(
      "Fixture \(url.lastPathComponent), \(outputs.count) source(s), audio \(timing.duration)s, release-to-final-text \(timing.finalization), elapsed \(started.duration(to: .now)), main actor p95 scheduling delay \(latency * 1_000) ms"
    )
    for (index, output) in outputs.enumerated() {
      let snapshot = output.snapshot
      print("Source \(index + 1): \(snapshot.text)")
      if !snapshot.failures.isEmpty {
        throw SpeechError.unavailable(snapshot.failures.joined(separator: "; "))
      }
    }
  }
}

private final class BenchmarkOutput: Sendable {
  private struct State {
    var text = ""
    var failures: [String] = []
  }
  private let state = Mutex(State())
  func receive(_ phrase: SpeechPhrase) {
    guard phrase.isFinal else { return }
    state.withLock { $0.text += " " + phrase.text }
  }
  func fail(_ message: String) { state.withLock { $0.failures.append(message) } }
  var snapshot: (text: String, failures: [String]) { state.withLock { ($0.text, $0.failures) } }
}

@MainActor
private final class MainActorProbe {
  private static let interval: TimeInterval = 0.02
  private static let maximumSamples = 5_000
  private var delays: [Double] = []
  func measure() async {
    while !Task.isCancelled && delays.count < Self.maximumSamples {
      let start = ProcessInfo.processInfo.systemUptime
      do { try await Task.sleep(for: .seconds(Self.interval), tolerance: .zero) } catch { return }
      delays.append(max(0, ProcessInfo.processInfo.systemUptime - start - Self.interval))
    }
  }
  var percentile95: Double {
    let sorted = delays.sorted()
    return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
  }
}
