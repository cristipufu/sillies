import Foundation
import SilliesInference
import SilliesModelStore
import SilliesTTS

struct VoiceProfileBenchmark {
  private static let requestCount = 5
  let store: ModelStore
  let provider: any TTSProvider
  let manifest: TTSModelManifest
  let request: SpeechSynthesisRequest

  private struct Preparation {
    let total: TimeInterval
    let beforeProvider: TimeInterval
  }

  private struct Report: Codable {
    let modelID: String
    let revision: String
    let preparationSeconds: TimeInterval
    let beforeProviderSeconds: TimeInterval
    let verificationReplaySeconds: TimeInterval
    let delivery: VoiceProfileSamples.Delivery
    let requests: [VoiceProfileSamples.Report]
  }

  func run() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let path = environment["SILLIES_VOICE_PROFILE_DIRECTORY"], path.hasPrefix("/"),
      let delivery = VoiceProfileSamples.Delivery(
        rawValue: environment["SILLIES_VOICE_PROFILE_DELIVERY"] ?? "drain")
    else { throw TTSError.invalidRequest }
    let directory = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let measuredProvider = VoiceProfileProvider(provider)
    let registry = try TTSModelRegistry(
      store: store, providers: [measuredProvider], activity: InferenceActivity())
    do {
      let preparation = try await measurePreparation(registry, provider: measuredProvider)
      let reports = try await synthesizeRequests(
        using: registry, delivery: delivery, directory: directory)
      await registry.stop()
      let report = Report(
        modelID: manifest.modelID, revision: manifest.revision,
        preparationSeconds: preparation.total, beforeProviderSeconds: preparation.beforeProvider,
        verificationReplaySeconds: try await replayVerification(), delivery: delivery,
        requests: reports)
      try write(report, to: directory)
    } catch {
      await registry.stop()
      throw error
    }
  }

  private func measurePreparation(_ registry: TTSModelRegistry, provider: VoiceProfileProvider)
    async throws -> Preparation
  {
    let started = ProcessInfo.processInfo.systemUptime
    guard
      try await registry.prepareVoiceIfPossible(
        request.voice, using: manifest, conversationID: UUID())
    else { throw TTSError.busy }
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    guard let providerStarted = await provider.preparationStartedAt else {
      throw TTSError.interrupted
    }
    return .init(total: elapsed, beforeProvider: providerStarted - started)
  }

  private func synthesizeRequests(
    using registry: TTSModelRegistry, delivery: VoiceProfileSamples.Delivery, directory: URL
  ) async throws -> [VoiceProfileSamples.Report] {
    var reports: [VoiceProfileSamples.Report] = []
    for index in 0..<Self.requestCount {
      let samples = VoiceProfileSamples(delivery: delivery)
      try await registry.synthesize(request, using: manifest) { try await samples.append($0) }
      let report = await samples.report()
      reports.append(report)
      try await samples.writeAudio(to: directory.appendingPathComponent("request-\(index).wav"))
      print("Request \(index): \(report.elapsedSeconds)s, \(report.sampleCount) samples")
    }
    return reports
  }

  private func replayVerification() async throws -> TimeInterval {
    let started = ProcessInfo.processInfo.systemUptime
    let lease = try await store.acquire(manifest)
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    await lease.close()
    return elapsed
  }

  private func write(_ report: Report, to directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(
      to: directory.appendingPathComponent("client.json"), options: .atomic)
  }
}
