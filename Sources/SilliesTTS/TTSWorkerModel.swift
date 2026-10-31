import Foundation
import SilliesInference

actor TTSWorkerModel: PreparedTTSModel {
  private static let responseTimeout: TimeInterval = 180
  private static let maximumAudioSeconds = 60
  private let configuration: TTSPreparation
  private let executable: URL
  private var connection: InferenceWorkerConnection?
  private var busy = false

  init(configuration: TTSPreparation, executable: URL) {
    self.configuration = configuration
    self.executable = executable
  }

  func synthesize(_ request: SpeechSynthesisRequest, receive: SynthesizedAudioSink) async throws {
    try request.validate()
    guard !busy else { throw TTSError.busy }
    busy = true
    defer { busy = false }
    try Task.checkCancellation()
    let worker = try connection ?? InferenceWorkerConnection(executable: executable)
    connection = worker
    let message = TTSInferenceRequest(configuration: configuration, synthesis: request)
    try await withTaskCancellationHandler {
      do {
        try Task.checkCancellation()
        try await Task.detached(priority: .userInitiated) {
          try worker.send(message, timeout: Self.responseTimeout)
        }.value
        try await consume(worker, receive: receive)
      } catch {
        worker.stop()
        await worker.reap()
        connection = nil
        throw error
      }
    } onCancel: {
      worker.stop()
    }
  }

  private func consume(_ worker: InferenceWorkerConnection, receive: SynthesizedAudioSink)
    async throws
  {
    var seconds: Double = 0
    var sampleRate: Int?
    while true {
      try Task.checkCancellation()
      let response = try await Task.detached(priority: .userInitiated) {
        try worker.receive(TTSInferenceResponse.self, timeout: Self.responseTimeout)
      }.value
      switch response {
      case .audio(let audio):
        try audio.validate()
        guard sampleRate == nil || sampleRate == audio.sampleRate else {
          throw TTSError.invalidAudio
        }
        sampleRate = audio.sampleRate
        seconds += Double(audio.samples.count) / Double(audio.sampleRate)
        guard seconds <= Double(Self.maximumAudioSeconds) else { throw TTSError.invalidAudio }
        try await receive(audio)
        try await Task.detached(priority: .userInitiated) {
          try worker.send(TTSInferenceAcknowledgement.consumed, timeout: Self.responseTimeout)
        }.value
      case .finished:
        guard seconds > 0 else { throw TTSError.invalidAudio }
        return
      case .failure(let message):
        throw TTSError.unavailable(message)
      }
    }
  }

  func stop() async {
    guard let worker = connection else { return }
    connection = nil
    worker.stop()
    await worker.reap()
  }
}
