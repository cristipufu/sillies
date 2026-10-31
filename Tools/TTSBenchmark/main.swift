import Foundation
import SilliesInference
import SilliesModelStore
import SilliesTTS

/// Bounded, opt-in real-model check. Normal tests use injected runtimes and never download weights.
@main enum TTSBenchmark {
  static func main() async {
    do { try await run() } catch {
      fputs("Voice model check failed: \(error.localizedDescription)\n", stderr)
      exit(EXIT_FAILURE)
    }
  }

  private static func run() async throws {
    let arguments = CommandLine.arguments
    guard [4, 6].contains(arguments.count), ["install", "run"].contains(arguments[1]) else {
      fputs("Usage: TTSBenchmark install|run MODEL_ID MODEL_DIRECTORY [LANGUAGE TEXT]\n", stderr)
      exit(EXIT_FAILURE)
    }
    guard
      let manifest = try TTSModelCatalog.bundled().manifests.first(where: {
        $0.modelID == arguments[2]
      })
    else { throw TTSError.unavailable("Unknown voice model.") }
    let directory = URL(fileURLWithPath: arguments[3])
    let store = ModelStore(root: directory)
    if arguments[1] == "install" {
      try await store.install(manifest) { _ in }
      print("Verified installation: \(manifest.model.name)")
      return
    }
    let executable =
      ProcessInfo.processInfo.environment["SILLIES_TTS_HELPER"].map {
        URL(fileURLWithPath: $0)
      }
      ?? URL(fileURLWithPath: arguments[0]).deletingLastPathComponent()
      .appendingPathComponent("SilliesTTSInference")
    let registry = try TTSModelRegistry(
      store: store,
      providers: [WorkerTTSProvider(id: manifest.model.providerID, executable: executable)],
      activity: InferenceActivity())
    let samples = SampleCollector()
    let started = ContinuousClock.now
    let language = arguments.count == 6 ? arguments[4] : "en"
    let passage =
      arguments.count == 6
      ? arguments[5] : "Hello! I’m your little window companion. What’s on your mind?"
    guard let voice = manifest.model.voices.first else { throw TTSError.unsupportedVoice }
    do {
      try await registry.synthesize(
        .init(text: passage, voiceID: voice.id, language: language),
        using: manifest
      ) { audio in await samples.append(audio) }
      await registry.stop()
      let report = try await samples.write(
        to: directory.appendingPathComponent(manifest.modelID + ".wav"))
      print("\(manifest.model.name): \(report); elapsed \(started.duration(to: .now))")
    } catch {
      await registry.stop()
      throw error
    }
  }
}

private actor SampleCollector {
  private let started = ContinuousClock.now
  private var firstAudio: Duration?
  private var samples: [Float] = []
  private var sampleRate = 0
  func append(_ audio: SynthesizedAudio) {
    if firstAudio == nil { firstAudio = started.duration(to: .now) }
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
      "\(Double(samples.count) / Double(sampleRate)) seconds of valid audio → \(url.path); first audio \(firstAudio ?? .zero)"
  }
}
