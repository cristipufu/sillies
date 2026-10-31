import Darwin
import Foundation
import SilliesFishSpeech
import SilliesInference
import SilliesTTS

@main enum TTSInferenceMain {
  private static let idleTimeout: TimeInterval = 90
  private static let responseTimeout: TimeInterval = 180
  private static let maximumGPUOperationsPerBuffer = 8

  static func main() async {
    let parentMonitor = InferenceParentMonitor.start()
    defer { parentMonitor.cancel() }
    // Keep MLX command buffers short so window composition can share the GPU during speech.
    guard setenv("MLX_MAX_OPS_PER_BUFFER", String(maximumGPUOperationsPerBuffer), 1) == 0 else {
      fputs("Could not configure the voice inference GPU budget.\n", stderr)
      exit(EXIT_FAILURE)
    }
    if let library = Bundle.main.url(forResource: "mlx", withExtension: "metallib") {
      FishSpeechEngine.configureMetalLibrary(library)
    }
    if CommandLine.arguments.contains("--self-test") {
      do { try FishSpeechEngine.validateCompute() } catch {
        fputs("TTS GPU self-test failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
      }
      print("Native TTS helper and GPU: available (Kokoro, Pocket TTS, Qwen3-TTS, Fish S2 Pro)")
      return
    }
    // Vendor diagnostics may write to stdout. Reserve a private descriptor for framed messages.
    let descriptor = dup(STDOUT_FILENO)
    guard descriptor >= 0, dup2(STDERR_FILENO, STDOUT_FILENO) >= 0,
      fcntl(descriptor, F_SETNOSIGPIPE, 1) != -1,
      fcntl(descriptor, F_SETFL, O_NONBLOCK) != -1
    else { exit(EXIT_FAILURE) }
    let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    let runtime = NativeTTSRuntime(factories: [
      "kokoro": { try await KokoroTTSModel(configuration: $0) },
      "pocket-tts": { try await PocketTTSModel(configuration: $0) },
      "qwen3-tts": { try await QwenTTSModel(configuration: $0) },
      "fish-speech": { try FishTTSModel(configuration: $0) },
    ])
    while true {
      let request: TTSInferenceRequest
      do {
        request = try InferenceWire.read(
          TTSInferenceRequest.self, from: .standardInput, deadline: deadline(Self.idleTimeout))
      } catch { return }
      let result: TTSInferenceResponse
      do {
        try await runtime.synthesize(request) { samples, sampleRate in
          try send(samples, sampleRate: sampleRate, output: output)
        }
        result = .finished
      } catch {
        fputs("Speech synthesis failed: \(error.localizedDescription)\n", stderr)
        result = .failure(error.localizedDescription)
      }
      do {
        try InferenceWire.write(result, to: output, deadline: deadline(Self.responseTimeout))
      } catch { return }
    }
  }

  private static func send(_ samples: [Float], sampleRate: Int, output: FileHandle) throws {
    for start in stride(from: 0, to: samples.count, by: SynthesizedAudio.maximumChunkSamples) {
      let end = min(start + SynthesizedAudio.maximumChunkSamples, samples.count)
      let audio = try SynthesizedAudio(samples: Array(samples[start..<end]), sampleRate: sampleRate)
      try InferenceWire.write(
        TTSInferenceResponse.audio(audio), to: output, deadline: deadline(Self.responseTimeout))
      _ = try InferenceWire.read(
        TTSInferenceAcknowledgement.self, from: .standardInput,
        deadline: deadline(Self.responseTimeout))
    }
  }

  private static func deadline(_ timeout: TimeInterval) -> TimeInterval {
    ProcessInfo.processInfo.systemUptime + timeout
  }
}
