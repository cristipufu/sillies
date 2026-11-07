import Darwin
import Foundation
import MLX
import SilliesCore
import SilliesInference
import SilliesSearchModels

@main enum SearchInferenceMain {
  static func main() async {
    let parent = InferenceParentMonitor.start()
    defer { parent.cancel() }
    if let library = Bundle.main.url(forResource: "mlx", withExtension: "metallib") {
      GPU.metallib = library
    }
    // Native libraries may print progress. Keep those bytes out of the framed protocol.
    let protocolDescriptor = dup(STDOUT_FILENO)
    guard protocolDescriptor >= 0, dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else { return }
    let protocolOutput = FileHandle(fileDescriptor: protocolDescriptor, closeOnDealloc: true)
    _ = fcntl(protocolDescriptor, F_SETNOSIGPIPE, 1)
    _ = fcntl(protocolDescriptor, F_SETFL, O_NONBLOCK)
    let runtime = SearchEmbeddingRuntime()
    while true {
      let request: EmbeddingRequest
      do {
        request = try InferenceWire.read(
          EmbeddingRequest.self, from: .standardInput, deadline: .infinity)
      } catch { return }
      let response: EmbeddingResponse
      do { response = try await runtime.respond(to: request) } catch {
        fputs("Local memory embedding failed: \(error)\n", stderr)
        response = .init(failure: error.localizedDescription)
      }
      do {
        try InferenceWire.write(
          response, to: protocolOutput, deadline: ProcessInfo.processInfo.systemUptime + 30)
      } catch { return }
    }
  }
}
